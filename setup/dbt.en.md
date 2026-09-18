# Configure dbt with Snowflake

[中文](dbt.md) | English

dbt is installed in the Airflow image. The `dev` target points to `STREAMIFY_STG`, and `prod` points to `STREAMIFY_PROD`.

Complete [Initialize Snowflake](../snowflake/README.en.md), then build and check:

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

The core models use Snowflake staging `listen_events` and the songs and state-codes seeds to build dimensions, facts, and a wide view. `page_view_events` and `auth_events` are loaded but do not yet feed the core models.
