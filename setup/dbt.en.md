# Configure dbt with Snowflake

[中文](dbt.md) | English

dbt is installed in the Airflow image. The `dev` target points to `STREAMIFY_STG`, and `prod` points to `STREAMIFY_PROD`.

Complete [Initialize Snowflake](../airflow/snowflake_setup.en.md), then build and check:

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

Before the first production DAG run, manually run `load_songs_dag` once in the Airflow UI. `streamify_dag` loads the `state_codes` seed itself and then runs `dbt run --target prod`.

Your exercise is `dbt/models/core/dim_user_agents.sql`: build a user-agent dimension from `listen_events`. It is disabled so the main DAG is unaffected. After writing the SQL, remove `enabled=false` and run it separately with `dbt run --select dim_user_agents --target prod`. The next step is adding its `userAgentKey` to `fact_streams`.
