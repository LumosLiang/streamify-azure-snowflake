# 配置 dbt 与 Snowflake

中文 | [English](dbt.en.md)

dbt 安装在 Airflow 镜像中。`dev` target 指向 `STREAMIFY_STG`，`prod` target 指向 `STREAMIFY_PROD`。

先完成 [Snowflake 初始化](../snowflake/README.md)，然后构建并检查：

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

核心模型从 Snowflake staging 中的 `listen_events` 和歌曲、州代码 seed 构建维度表、事实表与宽表；`page_view_events` 和 `auth_events` 目前只入仓，不参与核心模型。
