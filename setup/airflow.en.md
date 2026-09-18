# Run Airflow on an Azure VM

[中文](airflow.md) | English

Airflow first loads Parquet files from ADLS2 into Snowflake staging tables, then invokes dbt to build the warehouse models.

## Start

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

See [Initialize Snowflake](../airflow/snowflake_setup.en.md) for the one-time Snowflake and ADLS2 setup. This change adds the Snowflake provider, so an existing installation must rebuild the image; `airflow_startup.sh` does that.

Use [SSH port forwarding](ssh.en.md#4-port-forwarding) and open `http://localhost:8080`. The default username and password are both `airflow`.

## DAGs

- `load_songs_dag`: run once manually to load the bundled `songs.csv` dbt seed into `STREAMIFY_STG`.
- `dbt_test`: your DAG exercise; its goal is to compile the dbt project with `BashOperator`.
- `streamify_dag`: hourly COPY of three event types from ADLS2, followed by dbt.

There are now two exercise files: `dbt_test_dag.py` for DAG syntax and `auth_events.sql` for Snowflake COPY. Both contain TODO guidance and do not prevent you from reading the main DAG.
