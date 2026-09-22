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

脚本安装 Java 17 和 Spark 4.1.3，并创建 `~/.spark_env`。三台 VM 必须使用相同版本。

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

在 master 的 `spark_streaming/` 目录创建 Parquet 作业配置：

```bash
mkdir -p "$HOME/.config/streamify"
cp spark-parquet.env.example "$HOME/.config/streamify/spark-parquet.env"
source "$HOME/.config/streamify/spark-parquet.env"
```

将其中的 `<...>` 替换为当前值。`SPARK_MASTER_URL` 供 `spark-submit` 调度作业，`KAFKA_ADDRESS` 供作业读取 topics，`AZURE_STORAGE_ACCOUNT` 指向现有 Parquet 数据湖。`stream_all_events.py` 默认使用 `streamify` container，所以不需要配置 `AZURE_STORAGE_CONTAINER`。

之后每次运行 Parquet 作业前只需加载一次这个文件。Spark master 和 Kafka VM 使用私网地址；同一 VNet 内的 VM 可以通过私网通信。

Terraform 已向三台 Spark VM 的 managed identity 授予容器级 `Storage Blob Data Contributor`
权限。作业通过 ABFS 和 VM 身份写入 ADLS，不需要 Azure 密钥。

### 4. 验证集群和 Kafka

先在三台 VM 上分别确认版本。三台输出中的 Java 主版本应为 `17`，Spark 版本应为 `4.1.3`：

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
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.3 \
  validate_kafka.py
```

成功时会输出 `Kafka metadata validation passed`。

### 5. 提交流处理作业

只在 master 上运行：

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.3,org.apache.spark:spark-hadoop-cloud_2.13:4.1.3 \
  stream_all_events.py
```

`spark-hadoop-cloud` 提供访问 ADLS 所需的 Hadoop cloud connector 及其依赖。

正常运行后，ADLS 容器中会每两分钟为每个 topic 写入 Parquet 文件和 checkpoint。
路径形如：

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

### 6. 向 Iceberg 提交流处理作业

`stream_listen_events_iceberg.py` 消费 `listen_events`，并写入 `streamify_raw.listen_events`。Polaris 为表文件下发短期 SAS；Spark VM 的 managed identity 则向同一账号中独立的 `streamify-checkpoints` container 写入 checkpoint。

作业已完成运行验证：Kafka micro-batch 已提交到 Iceberg，checkpoint container 也已写入状态文件。现有 Parquet 流作业保持不变。

在 Spark Master 的 `spark_streaming/` 目录创建组件配置：

```bash
mkdir -p "$HOME/.config/streamify"
cp spark-iceberg.env.example "$HOME/.config/streamify/spark-iceberg.env"
```

将其中的 `<...>` 替换为当前值。此文件统一保存 Spark、Kafka、Polaris catalog 和 checkpoint 参数，并加载持久化的 Spark principal；每次提交前只需加载一次：

```bash
source "$HOME/.config/streamify/spark-iceberg.env"
```

各字段的作用如下：

| 字段 | 作用 |
| --- | --- |
| `source "$HOME/.spark_env"` | 加载 Spark 安装时已配置的 Java、`SPARK_HOME` 和 `PATH`。 |
| `source "$HOME/.polaris_spark.env"` | 加载 Spark principal 的 OAuth 凭据 `POLARIS_SPARK_CLIENT_ID` 和 `POLARIS_SPARK_CLIENT_SECRET`。 |
| `SPARK_MASTER_URL` | 指向 standalone Spark Master，`spark-submit` 据此把 driver 和 executors 调度到集群。 |
| `KAFKA_ADDRESS` | Kafka VM 的私网地址；作业通过它连接 `listen_events` topic。 |
| `POLARIS_CATALOG_NAME` | Polaris 中 Azure catalog 的名称，决定 Iceberg 表所在的 Storage Account、container 和根路径。 |
| `ICEBERG_CHECKPOINT_STORAGE_ACCOUNT` | Structured Streaming checkpoint 所在的 ADLS Storage Account，由 Spark VM managed identity 写入，不属于 Iceberg 表。 |

`iceberg_config.py` 中的 `build_streaming_config()` 只读取一次这些环境变量，并构造 `StreamingConfig`。主作业把这个显式配置对象传给 Spark session、Kafka reader、建表和 writer；这些函数不在内部读取环境变量。

`ICEBERG_NAMESPACE`、`ICEBERG_TABLE` 和 `ICEBERG_CHECKPOINT_CONTAINER` 使用代码默认值 `streamify_raw`、`listen_events` 和 `streamify-checkpoints`，因此不必写入配置文件。Iceberg 表路径由 Polaris catalog 决定；checkpoint 不属于 Iceberg 表，位于独立 container，不会被 Iceberg 表维护操作处理。

提交命令为：

```bash
spark-submit \
  --master "$SPARK_MASTER_URL" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.3,org.apache.spark:spark-hadoop-cloud_2.13:4.1.3,org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0,org.apache.iceberg:iceberg-azure-bundle:1.11.0 \
  stream_listen_events_iceberg.py
```

`create_kafka_read_stream()` 默认从 `earliest` 读取。新 checkpoint 首次启动时会处理 Kafka 仍保留的旧消息。Iceberg 的 Structured Streaming 写入使用 `DataStreamWriter.toTable()`，表必须先创建。参考：[Iceberg Structured Streaming](https://iceberg.apache.org/docs/latest/spark-structured-streaming/)。

### 7. 停止集群

在 master 上停止 master，在每个 worker 上停止 worker：

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

读取的 Kafka topics：`listen_events`、`page_view_events`、`auth_events`。
