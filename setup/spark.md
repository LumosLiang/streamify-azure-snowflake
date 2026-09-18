## 在 Azure VM 上搭建 Spark Standalone 集群

[English](spark.en.md)

Terraform 创建三台 Azure VM：一台 Spark master 和两台 worker。Spark 使用 standalone 模式，Kafka 运行在独立的 Kafka VM
上，Spark 通过 Kafka VM 的私网地址访问 `9092`。

Terraform 只创建基础设施，不会自动安装或启动 Spark。先完成 [Terraform 部署](terraform.md)、
[SSH 配置](ssh.md) 和 [Kafka 部署](kafka.md)。

### 1. 在三台 VM 安装 Spark

在 master、worker-1、worker-2 上分别执行：
  
```bash
bash scripts/spark_setup.sh
```

脚本安装 Java 17 和 Spark 4.2.0，并创建 `~/.spark_env`。三台 VM 必须使用相同版本。

### 2. 启动 master 和 workers

先在 master 上查询私网 IP：

```bash
hostname -I
```

在 master 上启动 standalone master：

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-master.sh"
```

在两个 worker 上执行下面命令，把地址替换为 master 的私网 IP：

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-worker.sh" spark://<spark-master-private-ip>:7077
```

回到 master 检查集群：

```bash
jps
curl http://localhost:8080
```

Spark Web UI 默认监听 master 的 `8080`；通过 SSH 转发到本机 `8082` 的方法见 [SSH 配置](ssh.md)。

### 3. 配置连接信息

在 master 上进入流处理目录并设置：

```bash
cd ~/streamify-azure-snowflake/spark_streaming
export SPARK_MASTER_URL="spark://<spark-master-private-ip>:7077"
export KAFKA_ADDRESS="<kafka-private-ip>"
export AZURE_STORAGE_ACCOUNT="<storage-account-name>"
export AZURE_STORAGE_CONTAINER="streamify"
```

这里使用 Spark master 和 Kafka VM 的私网 IP。同一 VNet 内的 VM 可以通过私网通信。

Terraform 已向三台 Spark VM 的 managed identity 授予容器级 `Storage Blob Data Contributor`
权限。作业通过 ABFS 和 VM 身份写入 ADLS，不需要 Azure 密钥。

### 4. 验证集群和 Kafka

先在三台 VM 上分别确认版本。三台输出中的 Java 主版本应为 `17`，Spark 版本应为 `4.2.0`：

```bash
java -version
"${SPARK_HOME}/bin/spark-submit" --version
```

在 master 上确认两个 worker 已注册并处于 `ALIVE` 状态：

```bash
curl -fsS http://localhost:8080/json/ | python3 -c \
  'import json, sys; data=json.load(sys.stdin); workers=data["workers"]; assert len(workers) == 2 and all(worker["state"] == "ALIVE" for worker in workers); print("Spark master-worker validation passed")'
```

如果 Worker 没有注册，在对应 Worker 上检查进程和日志：

```bash
jps
ls -lt "${SPARK_HOME}/logs" | head
```

运行 Kafka smoke test，确认 Spark 可以加载 connector 并访问指定 topic：

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0 \
  validate_kafka.py
```

成功时会输出 `Kafka metadata validation passed`。

### 5. 提交流处理作业

只在 master 上运行：

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0,org.apache.spark:spark-hadoop-cloud_2.13:4.2.0 \
  stream_all_events.py
```

`spark-hadoop-cloud` 提供访问 ADLS 所需的 Hadoop cloud connector 及其依赖。

正常运行后，ADLS 容器中会每两分钟为每个 topic 写入 Parquet 文件和 checkpoint。
路径形如：

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

### 6. 停止集群

在 master 上停止 master，在每个 worker 上停止 worker：

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

读取的 Kafka topics：`listen_events`、`page_view_events`、`auth_events`。
