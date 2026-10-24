# Run Airflow on an Azure VM

[中文](airflow.md) | English

Airflow loads Parquet files from ADLS Gen2 into Snowflake staging tables and invokes dbt to build warehouse models. It can also call Spark SQL over SSH to compact Iceberg data files and expire snapshots older than seven days. The continuous Iceberg writer runs separately; this DAG does not start or stop it.

## Start

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

See [Initialize Snowflake](../snowflake/README.en.md) for the one-time Snowflake and ADLS2 setup. `build` builds the dependency image, `init` initializes the database, and `start` starts services. With no argument, the script defaults to `start`.

For an existing environment, use `bash scripts/airflow_startup.sh start`. DAG, SQL, and dbt files are already mounted, so editing them does not require a build. After editing `airflow/.env`, run `start` to recreate containers whose configuration changed. After changing the Dockerfile or `requirements.txt`, run `build`, then `start`. These operations preserve the database volume; configuration changes may briefly interrupt services.

Use [SSH port forwarding](ssh.en.md#4-port-forwarding) and open `http://localhost:8080`. The default username and password are both `airflow`.

## DAGs

- `load_songs_dag`: run once manually to load the bundled `songs.csv` dbt seed into `STREAMIFY_STG`.
- `streamify_dag`: hourly COPY of three event types from ADLS2, followed by dbt.
- `iceberg_maintenance_dag`: runs compaction, then snapshot expiration, every day at 03:00 UTC. It starts paused on first creation; enable it after configuring the connection and completing a manual run.

## Iceberg maintenance

The two tasks use the `spark_master_ssh` connection to run `scripts/spark_iceberg_maintenance.sh compact` and `expire` on the Spark Master. The expiration branch calculates the current UTC time minus seven days at execution time and calls `expire_snapshots(older_than => ..., retain_last => 1)`. The user has manually verified compaction; expiration and Airflow scheduling still need runtime verification. Orphan-file removal and manifest rewrites are outside this maintenance DAG.

After pulling the script on the **Spark Master**, run `cd ~/streamify-azure-snowflake && bash scripts/spark_iceberg_maintenance.sh expire`. A successful Spark SQL call returns counts of deleted data, manifest, and other files; zero is valid if no snapshots have reached seven days. You can also inspect `polaris.streamify_raw.listen_events.snapshots` to confirm recent snapshots remain available.

The Airflow worker already mounts `airflow/secrets/` read-only at `/opt/airflow/secrets/`. On the **Airflow VM**, create a dedicated SSH key in the repository:

```bash
cd ~/streamify-azure-snowflake
mkdir -p airflow/secrets
ssh-keygen -t ed25519 -f "$HOME/streamify-azure-snowflake/airflow/secrets/iceberg_maintenance_ed25519" -N ''
```

On the **Mac**, add the public key to the Spark Master's authorized keys for the same VM user. The SSH aliases are documented in [SSH setup](ssh.en.md#2-configure-ssh-aliases):

```bash
ssh streamify-airflow 'cat ~/streamify-azure-snowflake/airflow/secrets/iceberg_maintenance_ed25519.pub' \
  | ssh streamify-spark-master 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
```

In the Airflow UI, create an **Admin → Connections** entry named `spark_master_ssh` with type `SSH`. Set Host to the Spark Master's **private IP** (see [SSH connection details](ssh.en.md#1-find-connection-details)), Username to its VM login user, and Port to `22`. Set Extra to:

```json
{"key_file": "/opt/airflow/secrets/iceberg_maintenance_ed25519", "look_for_keys": false}
```

After pulling the update on the Airflow VM, run `bash scripts/airflow_startup.sh build` and `bash scripts/airflow_startup.sh start` from the project root to load the SSH provider in the worker. Trigger `iceberg_maintenance_dag` manually in the UI. Once both tasks succeed, check that Spark SQL and Snowflake can still query the Iceberg table, then unpause the DAG for daily runs. `is_paused_upon_creation` only affects a newly created DAG; check the pause state in the UI if the DAG already exists. References: [Airflow SSH Connection](https://airflow.apache.org/docs/apache-airflow-providers-ssh/stable/connections/ssh.html), [SSHOperator](https://airflow.apache.org/docs/apache-airflow-providers-ssh/stable/operators/ssh.html), and [Iceberg Spark procedures](https://iceberg.apache.org/docs/latest/spark-procedures/).
