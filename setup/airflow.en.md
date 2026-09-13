# Set Up Airflow on an Azure VM

[中文](airflow.md) | English

Airflow runs in Docker Compose on its own VM. This step only starts Airflow; it does not adapt or run the original DAGs.

## 1. Prepare the VM

Connect from your Mac and get the project:

```bash
ssh streamify-airflow
git clone https://github.com/LumosLiang/streamify-azure-snowflake.git
cd streamify-azure-snowflake
bash scripts/vm_setup.sh
```

Log out and reconnect so Docker group membership takes effect:

```bash
exit
ssh streamify-airflow
cd streamify-azure-snowflake
```

## 2. Create the local configuration

```bash
cp airflow/.env.example airflow/.env
sed -i "s/^AIRFLOW_UID=.*/AIRFLOW_UID=$(id -u)/" airflow/.env
```

See [Initialize Snowflake](../airflow/snowflake_setup.en.md) to create the user and key pair. Edit `airflow/.env` and set the account identifier and private-key passphrase. This file is ignored by Git and must not be committed.

## 3. Start and verify

The startup script expects the project at `~/streamify`. If the directory has a different name, create a link first:

```bash
ln -sfn "$HOME/streamify-azure-snowflake" "$HOME/streamify"
bash scripts/airflow_startup.sh
cd airflow
docker compose ps
```

Use [SSH port forwarding](ssh.en.md#4-port-forwarding) and open `http://localhost:8080`. The default username and password are both `airflow`.

```bash
docker compose logs --follow
docker compose down
```

The original DAGs still target GCP and BigQuery. They are retained for reading, so DAG import errors are expected until a later adaptation step.
