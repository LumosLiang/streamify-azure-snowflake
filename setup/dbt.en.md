# Configure dbt with Snowflake

[中文](dbt.md) | English

dbt is installed in the custom Airflow image. This step only establishes the Snowflake connection; it does not run or adapt the original models.

## 1. Prepare the Snowflake settings

From the project directory on the Airflow VM:

```bash
test -f airflow/.env || cp airflow/.env.example airflow/.env
```

Set these values:

- `SNOWFLAKE_ACCOUNT`: the Snowflake account identifier, such as `organization-account`
- `SNOWFLAKE_USER`: the user for dbt
- `SNOWFLAKE_PASSWORD`: that user's password
- `SNOWFLAKE_ROLE`: the role used by dbt
- `SNOWFLAKE_DATABASE`: the target database
- `SNOWFLAKE_WAREHOUSE`: the warehouse that runs SQL

`dbt/profiles.yml` reads these environment variables. The dev and prod targets use the `STREAMIFY_STG` and `STREAMIFY_PROD` schemas.

## 2. Build and check

Build the image using the [Airflow setup](airflow.en.md), then run:

```bash
cd ~/streamify/airflow
docker compose run --rm airflow-worker dbt --version
docker compose run --rm airflow-worker dbt debug \
  --project-dir /opt/airflow/dbt \
  --profiles-dir /opt/airflow/dbt
```

`dbt debug` only checks configuration and connectivity. The original models still use BigQuery SQL, so do not run `dbt run` yet.
