# Set Up a Spark Standalone Cluster on Azure VMs

[中文](spark.md) | English

Terraform creates three Azure VMs for Spark: one master and two workers. Spark runs in standalone mode. Kafka runs on a separate VM, and Spark accesses it through the Kafka VM's private address on port `9092`.

Terraform creates the infrastructure only. It does not install or start Spark. Complete the [Terraform deployment](terraform.en.md), [SSH setup](ssh.en.md), and [Kafka deployment](kafka.en.md) first.

## 1. Install Spark on all three VMs

Run the following commands separately on the master, worker-1, and worker-2:

```bash
ssh streamify-spark
bash scripts/spark_setup.sh
```

The script installs Java 17 and Spark 4.1.3 and creates `~/.spark_env`. All three VMs must use the same versions.

## 2. Start the master and workers

First, find the master's private IP:

```bash
hostname -I
```

On the master, start the standalone master:

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-master.sh"
```

On each worker, replace the placeholder with the master's private IP:

```bash
source ~/.spark_env
"${SPARK_HOME}/sbin/start-worker.sh" spark://<spark-master-private-ip>:7077
```

Return to the master and check the cluster:

```bash
jps
curl http://localhost:8080
```

The Spark Web UI listens on the master's port `8080` by default. See the [SSH guide](ssh.en.md) for forwarding it to local port `8082`.

## 3. Configure connection settings

Create the Parquet job configuration from `spark_streaming/` on the master:

```bash
mkdir -p "$HOME/.config/streamify"
cp spark-parquet.env.example "$HOME/.config/streamify/spark-parquet.env"
source "$HOME/.config/streamify/spark-parquet.env"
```

Replace each `<...>` value with the current values. `SPARK_MASTER_URL` schedules the job through `spark-submit`, `KAFKA_ADDRESS` reads the topics, and `AZURE_STORAGE_ACCOUNT` identifies the existing Parquet data lake. `stream_all_events.py` defaults to the `streamify` container, so `AZURE_STORAGE_CONTAINER` is unnecessary.

Each later Parquet submission needs only one load of this file. The Spark master and Kafka VM use private addresses; VMs in the same VNet can communicate over them.

Terraform grants the managed identities of all three Spark VMs the `Storage Blob Data Contributor` role on the container. The job uses ABFS and the VM identities to write to ADLS, so no Azure key is required.

## 4. Validate the cluster and Kafka

Check the versions separately on all three VMs. The Java major version should be `17` and the
Spark version should be `4.1.3` on every node:

```bash
java -version
"${SPARK_HOME}/bin/spark-submit" --version
```

On the master, verify that both workers are registered and `ALIVE`:

```bash
curl -fsS http://localhost:8080/json/ | python3 -c \
  'import json, sys; data=json.load(sys.stdin); workers=data["workers"]; assert len(workers) == 2 and all(worker["state"] == "ALIVE" for worker in workers); print("Spark master-worker validation passed")'
```

If a worker is missing, check its process and logs:

```bash
jps
ls -lt "${SPARK_HOME}/logs" | head
```

Run the Kafka smoke test to confirm that Spark can load the connector and access the topic:

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.3 \
  validate_kafka.py
```

The command should print `Kafka metadata validation passed`.

## 5. Submit the streaming job

Run this only on the master:

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.3,org.apache.spark:spark-hadoop-cloud_2.13:4.1.3 \
  stream_all_events.py
```

`spark-hadoop-cloud` supplies the Hadoop cloud connector and dependencies required for ADLS.

When the job is running, it writes Parquet files and checkpoints for each topic every two minutes. The paths look like this:

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

## 6. Submit a streaming job to Iceberg

`stream_listen_events_iceberg.py` consumes `listen_events` and writes to `streamify_raw.listen_events`. Polaris vends short-lived SAS credentials for table files. The Spark VM managed identity writes checkpoints to the separate `streamify-checkpoints` container in the same account.

The job has been runtime-validated: Kafka micro-batches have committed to Iceberg, and the checkpoint container contains streaming state. The existing Parquet streaming job is unchanged.

Create the component runtime configuration from `spark_streaming/` on the Spark Master:

```bash
mkdir -p "$HOME/.config/streamify"
cp spark-iceberg.env.example "$HOME/.config/streamify/spark-iceberg.env"
```

Edit `~/.config/streamify/spark-iceberg.env` and replace each `<...>` value with the current Spark master, Kafka, Polaris catalog, and Iceberg checkpoint values. This file keeps the job runtime settings together and loads the persisted Spark principal. Each later session needs only one load:

```bash
source "$HOME/.config/streamify/spark-iceberg.env"
```

The fields have these roles:

| Field | Role |
| --- | --- |
| `source "$HOME/.spark_env"` | Loads Java, `SPARK_HOME`, and `PATH` configured during Spark installation. |
| `source "$HOME/.polaris_spark.env"` | Loads the Spark principal OAuth credentials: `POLARIS_SPARK_CLIENT_ID` and `POLARIS_SPARK_CLIENT_SECRET`. |
| `SPARK_MASTER_URL` | Points to the standalone Spark Master, which schedules the driver and executors. |
| `KAFKA_ADDRESS` | The Kafka VM private address used to connect to the `listen_events` topic. |
| `POLARIS_CATALOG_NAME` | The Azure catalog name in Polaris, which determines the Iceberg table Storage Account, container, and base path. |
| `ICEBERG_CHECKPOINT_STORAGE_ACCOUNT` | The ADLS Storage Account for Structured Streaming checkpoints, written by the Spark VM managed identity and not part of the Iceberg table. |

`build_streaming_config()` in `iceberg_config.py` reads these environment variables once and constructs `StreamingConfig`. The main job passes that explicit configuration object to the Spark session, Kafka reader, table creation, and writer, which do not read environment variables internally.

`ICEBERG_NAMESPACE`, `ICEBERG_TABLE`, and `ICEBERG_CHECKPOINT_CONTAINER` use the code defaults `streamify_raw`, `listen_events`, and `streamify-checkpoints`, so they do not need entries in the configuration file. The Polaris catalog determines the Iceberg table location. A checkpoint is not part of an Iceberg table; it lives in a separate container and is outside Iceberg table maintenance.

Submit the job with:

```bash
spark-submit \
  --master "$SPARK_MASTER_URL" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.1.3,org.apache.spark:spark-hadoop-cloud_2.13:4.1.3,org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0,org.apache.iceberg:iceberg-azure-bundle:1.11.0 \
  stream_listen_events_iceberg.py
```

`create_kafka_read_stream()` uses `earliest`, so the first run with a new checkpoint will process Kafka messages that are still retained. Iceberg Structured Streaming writes use `DataStreamWriter.toTable()`, and the table must exist first. See [Iceberg Structured Streaming](https://iceberg.apache.org/docs/latest/spark-structured-streaming/).

### Stop the Iceberg streaming job

For a foreground `spark-submit`, press `Ctrl-C`. If the job was started in the background and its PID was written to `~/streamify-iceberg-writer.pid`, run:

```bash
kill "$(cat "$HOME/streamify-iceberg-writer.pid")"
```

Do not delete the checkpoint. The next start with the same checkpoint path resumes from the committed Kafka offset.

## 7. Stop the cluster

On the master, stop the master process. On each worker, stop its worker process:

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

The job reads these Kafka topics: `listen_events`, `page_view_events`, and `auth_events`.
