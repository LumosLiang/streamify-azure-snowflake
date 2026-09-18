# 配置 dbt 与 Snowflake

中文 | [English](dbt.en.md)

dbt 安装在 Airflow 镜像中。`dev` target 指向 `STREAMIFY_STG`，`prod` target 指向 `STREAMIFY_PROD`。

先完成 [Snowflake 初始化](../airflow/snowflake_setup.md)，然后构建并检查：

```bash
cd ~/streamify-azure-snowflake
bash scripts/airflow_startup.sh
cd airflow
docker compose run --rm --entrypoint dbt airflow-worker debug \
  --project-dir /opt/airflow/dbt \
  --profiles-dir /opt/airflow/dbt
docker compose run --rm --entrypoint dbt airflow-worker compile \
  --project-dir /opt/airflow/dbt \
  --profiles-dir /opt/airflow/dbt \
  --target prod
```

首次运行正式 DAG 前，在 Airflow UI 手动运行一次 `load_songs_dag`。`streamify_dag` 会自行加载 `state_codes` seed，然后执行 `dbt run --target prod`。

练习文件是 `dbt/models/core/dim_user_agents.sql`：从 `listen_events` 构建 userAgent 维度。它暂时被禁用，不影响主 DAG；完成 SQL 后删除 `enabled=false`，用 `dbt run --select dim_user_agents --target prod` 单独运行。下一步再把它的 `userAgentKey` 接入 `fact_streams`。
