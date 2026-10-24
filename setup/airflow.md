# 在 Azure VM 上运行 Airflow

中文 | [English](airflow.en.md)

Airflow 负责把 ADLS Gen2 中的 Parquet 文件装入 Snowflake staging 表并调用 dbt 构建数仓模型。它还可以通过 SSH 调用 Spark SQL，定期合并 Iceberg 小文件并清理七天前的快照。Iceberg 的持续写入作业独立运行，不由这个 DAG 启停。

## 启动

```bash
ssh streamify-airflow
cd ~/streamify-azure-snowflake
git pull
test -f airflow/.env || cp airflow/.env.example airflow/.env
sed -i "s/^AIRFLOW_UID=.*/AIRFLOW_UID=$(id -u)/" airflow/.env
bash scripts/airflow_startup.sh build
bash scripts/airflow_startup.sh init
bash scripts/airflow_startup.sh start
cd airflow
docker compose ps
```

Snowflake 和 ADLS2 的首次配置见 [Snowflake 初始化](../snowflake/README.md)。`build` 构建依赖镜像，`init` 初始化数据库，`start` 启动服务；不传参数时默认 `start`。

已有环境日常只运行 `bash scripts/airflow_startup.sh start`。DAG、SQL 和 dbt 文件已挂载进容器，更新这些文件不需要 build；修改 `airflow/.env` 后运行 `start`，Compose 会重建配置变化的容器。修改 Dockerfile 或 `requirements.txt` 后依次运行 `build`、`start`。这些操作保留数据库 volume，服务配置更新时可能短暂中断。

按 [SSH 端口转发](ssh.md#4-端口转发) 打开 `http://localhost:8080`，默认用户名和密码均为 `airflow`。

## DAG

- `load_songs_dag`：手动运行一次，把 dbt 自带的 `songs.csv` seed 装入 `STREAMIFY_STG`。
- `streamify_dag`：每小时从 ADLS2 COPY 三类事件，然后运行 dbt。
- `iceberg_maintenance_dag`：每天 03:00 UTC 依次执行 compaction 和快照过期；首次创建时暂停，完成下面的连接和手动验证后再启用。

## Iceberg 维护

两个 task 通过 `spark_master_ssh` 连接到 Spark Master，分别运行 `scripts/spark_iceberg_maintenance.sh compact` 和 `expire`。后者在执行时计算当前 UTC 时间减七天，传给 Iceberg `expire_snapshots(older_than => ..., retain_last => 1)`。compaction 已由用户手动验证；快照过期和 Airflow 调度仍待运行验证。此维护不处理 orphan files 或 manifest 重写。

在 **Spark Master** 拉取包含脚本的版本后，先运行 `cd ~/streamify-azure-snowflake && bash scripts/spark_iceberg_maintenance.sh expire`。成功时 Spark SQL 返回删除的 data、manifest 等文件数量；如果表中没有七天前的快照，数量可以是零。还可查询 `polaris.streamify_raw.listen_events.snapshots`，确认七天内的快照仍在。

Airflow worker 已把 `airflow/secrets/` 只读挂载到 `/opt/airflow/secrets/`。在 **Airflow VM** 的项目目录生成供它使用的 SSH 密钥：

```bash
cd ~/streamify-azure-snowflake
mkdir -p airflow/secrets
ssh-keygen -t ed25519 -f "$HOME/streamify-azure-snowflake/airflow/secrets/iceberg_maintenance_ed25519" -N ''
```

在 **Mac** 上把公钥加入 Spark Master 的同一 VM 用户；下面的 SSH 别名见 [SSH 配置](ssh.md#2-配置-ssh-别名)：

```bash
ssh streamify-airflow 'cat ~/streamify-azure-snowflake/airflow/secrets/iceberg_maintenance_ed25519.pub' \
  | ssh streamify-spark-master 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
```

在 Airflow UI 的 **Admin → Connections** 创建 `spark_master_ssh`，类型选 `SSH`，Host 填 Spark Master 的 **私网 IP**（获取方式见 [SSH 连接信息](ssh.md#1-查看连接信息)），Username 填该 VM 的登录用户，Port 填 `22`；Extra 填：

```json
{"key_file": "/opt/airflow/secrets/iceberg_maintenance_ed25519", "look_for_keys": false}
```

拉取更新后，在 Airflow VM 的项目根目录执行 `bash scripts/airflow_startup.sh build` 和 `bash scripts/airflow_startup.sh start` 让 worker 加载 SSH provider，然后在 UI 手动触发 `iceberg_maintenance_dag`。两个 task 均成功后，检查 Spark SQL 查询仍能读表、Snowflake 仍能查询 Iceberg 表，再取消 DAG 暂停，启用每日调度。`is_paused_upon_creation` 只影响首次创建的 DAG；已存在的 DAG 要在 UI 确认暂停状态。参考 [Airflow SSH Connection](https://airflow.apache.org/docs/apache-airflow-providers-ssh/stable/connections/ssh.html)、[SSHOperator](https://airflow.apache.org/docs/apache-airflow-providers-ssh/stable/operators/ssh.html) 和 [Iceberg Spark procedures](https://iceberg.apache.org/docs/latest/spark-procedures/)。
