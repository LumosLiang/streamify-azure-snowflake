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

The script installs Java 17 and Spark 4.2.0 and creates `~/.spark_env`. All three VMs must use the same versions.

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

On the master, enter the streaming directory and set:

```bash
cd ~/streamify-azure-snowflake/spark_streaming
export SPARK_MASTER_URL="spark://<spark-master-private-ip>:7077"
export KAFKA_ADDRESS="<kafka-private-ip>"
export AZURE_STORAGE_ACCOUNT="<storage-account-name>"
export AZURE_STORAGE_CONTAINER="streamify"
```

Use the private IPs of the Spark master and Kafka VM. VMs in the same VNet can communicate over their private addresses.

Terraform grants the managed identities of all three Spark VMs the `Storage Blob Data Contributor` role on the container. The job uses ABFS and the VM identities to write to ADLS, so no Azure key is required.

## 4. Validate the cluster and Kafka

Check the versions separately on all three VMs. The Java major version should be `17` and the
Spark version should be `4.2.0` on every node:

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
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0 \
  validate_kafka.py
```

The command should print `Kafka metadata validation passed`.

## 5. Submit the streaming job

Run this only on the master:

```bash
spark-submit \
  --master "${SPARK_MASTER_URL}" \
  --packages org.apache.spark:spark-sql-kafka-0-10_2.13:4.2.0,org.apache.spark:spark-hadoop-cloud_2.13:4.2.0 \
  stream_all_events.py
```

`spark-hadoop-cloud` supplies the Hadoop cloud connector and dependencies required for ADLS.

When the job is running, it writes Parquet files and checkpoints for each topic every two minutes. The paths look like this:

```text
abfss://streamify@<storage-account-name>.dfs.core.windows.net/listen_events/
abfss://streamify@<storage-account-name>.dfs.core.windows.net/checkpoint/listen_events/
```

## 6. Stop the cluster

On the master, stop the master process. On each worker, stop its worker process:

```bash
"${SPARK_HOME}/sbin/stop-master.sh"
"${SPARK_HOME}/sbin/stop-worker.sh"
```

The job reads these Kafka topics: `listen_events`, `page_view_events`, and `auth_events`.
