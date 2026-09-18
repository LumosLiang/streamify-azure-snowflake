# 在 Azure VM 上运行 Airflow

中文 | [English](airflow.en.md)

Airflow 负责两步：先把 ADLS2 中的 Parquet 文件装入 Snowflake staging 表，再调用 dbt 构建数仓模型。

## 启动

```bash
ssh streamify-airflow
cd ~/streamify-azure-snowflake
git pull
test -f airflow/.env || cp airflow/.env.example airflow/.env
sed -i "s/^AIRFLOW_UID=.*/AIRFLOW_UID=$(id -u)/" airflow/.env
bash scripts/airflow_startup.sh
cd airflow
docker compose ps
```

Snowflake 和 ADLS2 的首次配置见 [Snowflake 初始化](../airflow/snowflake_setup.md)。本次增加了 Snowflake provider，因此已有安装必须重新构建镜像；`airflow_startup.sh` 会完成构建。

按 [SSH 端口转发](ssh.md#4-端口转发) 打开 `http://localhost:8080`，默认用户名和密码均为 `airflow`。

## DAG

- `load_songs_dag`：手动运行一次，把 dbt 自带的 `songs.csv` seed 装入 `STREAMIFY_STG`。
- `dbt_test`：留给你的 DAG 练习；目标是用 `BashOperator` 编译 dbt 项目。
- `streamify_dag`：每小时从 ADLS2 COPY 三类事件，然后运行 dbt。

现在有两个练习文件：`dbt_test_dag.py` 用于练习 DAG，`auth_events.sql` 用于练习 Snowflake COPY。两个文件都提供了 TODO，且不影响你阅读主 DAG。
