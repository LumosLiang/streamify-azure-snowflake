# Project model

## Purpose

Streamify simulates events from a music service and carries them through a
streaming and analytics pipeline. This fork keeps the original repository and
author history while replacing the GCP implementation with Azure infrastructure
and an AWS-hosted Snowflake warehouse.

The project is also a learning environment. Readability, visible boundaries,
and incremental changes matter more than hiding infrastructure behind managed
services or introducing a production platform prematurely.

## Current data flow

```text
Eventsim
  -> Kafka topics: listen_events, page_view_events, auth_events
  -> Spark Structured Streaming
  -> ADLS Gen2 streamify container
       <event-type>/month=<m>/day=<d>/hour=<h>/*.parquet
       checkpoint/<event-type>/...
  -> Snowflake external stage and hourly COPY INTO staging tables
  -> dbt seeds and dimensional models

Kafka listen_events
  -> parallel Spark Structured Streaming job
  -> Polaris REST catalog -> ADLS Gen2 Iceberg table
  -> Snowflake reads the table through a Polaris catalog integration

Airflow
  -> schedules Snowflake COPY INTO and dbt
  -> daily Iceberg maintenance DAG configured (runtime validation pending)
```

`status_change_events` may be produced by Eventsim, but the current Spark job
does not consume or persist it. The dbt core models primarily model
`listen_events`; page-view and authentication events are loaded to staging but
are not yet part of the dimensional model.

## Component ownership

| Area | Canonical files | Responsibility |
| --- | --- | --- |
| Azure IaC | `terraform/`, `setup/terraform*.md` | Five VMs, VNet/subnet/NSG/NICs, public IPs, ADLS Gen2, identities and RBAC |
| Host setup | `scripts/vm_setup.sh`, `setup/ssh*.md` | Ubuntu Docker installation and operator access |
| Event source | `eventsim/`, `scripts/eventsim_startup.sh` | Generate synthetic music-service events |
| Kafka | `kafka/docker-compose.yml`, `setup/kafka*.md` | KRaft broker, Schema Registry, Control Center and tools |
| Spark | `spark_streaming/`, `scripts/spark_setup.sh`, `setup/spark*.md` | Consume three Kafka topics into partitioned Parquet and checkpoints; a separate job writes `listen_events` to Iceberg |
| Snowflake | `snowflake/` | Roles, users, database/schema/warehouse, storage integration, file format and stage |
| Airflow | `airflow/`, `setup/airflow*.md` | Schedule Snowflake loads and dbt; Iceberg maintenance DAG is configured but runtime validation is pending |
| dbt | `dbt/`, `setup/dbt*.md` | Seeds, dimensions, fact table and wide view |
| Polaris | `polaris/`, `setup/polaris*.md` | Catalog and PostgreSQL metadata services; the Spark SQL validation table and the parallel Kafka-to-Iceberg `listen_events` path are verified |

## Runtime topology and identities

- Local Python development uses a root uv project and `.venv` with Python 3.12
  and PySpark 4.1.3. Airflow/dbt runtime dependencies remain in Docker.
- Airflow/Eventsim entry scripts expose build and run as separate operations.
  Eventsim reads local runtime parameters and a mounted JSON configuration;
  the Spark Iceberg writer and maintenance script share configurable Polaris
  endpoints. These file changes require deployment before affecting the VMs.
- Kafka VM: Kafka runs through Compose. New auto-created event topics default
  to four partitions; existing topics require an explicit online alteration.
  Eventsim is created manually by `scripts/eventsim_startup.sh` and has no
  restart policy.
- Airflow VM: Airflow Docker Compose stack; dbt is installed in the custom
  Airflow image and the repository `dbt/` directory is mounted into containers.
- Spark master and two workers: Spark 4.1.3 installed directly on Ubuntu 24.04.
- Spark VM managed identities have `Storage Blob Data Contributor` on the
  existing `streamify` container.
- Airflow VM managed identity has `Storage Blob Data Reader` on `streamify`.
- The deploying Azure user has `Storage Blob Data Reader` on both Storage
  Accounts.
- Snowflake uses its Azure enterprise application to read the existing container.
- Polaris uses a separate service principal with `Storage Blob Data Contributor`
  on the dedicated Iceberg Storage Account, which lets it mint ADLS
  user-delegation SAS. Spark VM managed identities have `Storage Blob Data
  Contributor` on the separate Iceberg checkpoint container.

Do not substitute one identity for another without tracing who performs the
actual data-plane operation.

## Implemented and observed

- The Azure/Snowflake chain has been set up and the user reported it working end
  to end through Airflow and dbt.
- Spark writes append-only Parquet every two minutes, partitioned by month, day,
  and hour, with separate checkpoint paths.
- Airflow schedules one active DAG run at a time, runs one `COPY INTO` task per
  event type, then `dbt seed` for state codes and `dbt run` against `prod`.
- `load_songs_dag` is a manual DAG that loads the bundled songs seed.
- Kafka uses KRaft and has no ZooKeeper. Its Compose configuration has no
  persistent data volume, so container replacement can lose broker data.
- Spark services and streaming applications require explicit startup; a remote
  shell is not a durable process supervisor.
- The parallel Iceberg writer has consumed `listen_events`, committed micro-batches
  to `streamify_raw.listen_events`, and created state in its checkpoint container.
- The user confirmed Snowflake can query `polaris.streamify_raw.listen_events`.
- The user ran `rewrite_data_files`; Iceberg's snapshots metadata showed append
  snapshots followed by a `replace` snapshot from compaction. Snapshot expiration
  has not yet been run, so old files visible in ADLS may still be referenced by
  retained snapshots.
- The live `listen_events` topic was expanded from one to four partitions. After
  a restart with the same checkpoint, the Iceberg writer resumed offsets for all
  four partitions. A short observation recorded roughly 25.5 produced events per
  second; it is not an end-to-end Spark throughput benchmark.

These statements describe repository intent plus user-reported results. An agent
must re-check live state before making operational claims.

## Work in progress and deferred decisions

The separate HNS-enabled Iceberg Storage Account, Polaris catalog, and Spark
principal are configured. Spark SQL validation succeeded, the Kafka-to-Iceberg
writer has committed data to `streamify_raw.listen_events`, and the user
confirmed Snowflake can query that table. A manual compaction was also observed
as a `replace` snapshot after the append snapshots.

`scripts/spark_iceberg_maintenance.sh compact` has passed manual runtime
validation according to the user. The script now also calls snapshot expiration
with a UTC cutoff of seven days and retains the latest snapshot. The Airflow DAG
is configured for 03:00 UTC daily, starts paused on first creation, and invokes
both operations through SSH. Expiration and Airflow execution have not yet been
runtime-verified; seven-day retention is not operational until the DAG is
deployed, manually tested, and unpaused.

The Airflow DAG only runs finite maintenance operations. It does not supervise
or restart the long-running Structured Streaming writer; that writer remains a
separately started process. Manifest rewriting and orphan-file cleanup are not
implemented.

The Azure SDK endpoint-parsing issue has a documented storage-account naming
workaround in `polaris/`. No custom Polaris image or source patch is deployed,
and no upstream issue or pull request has been filed. Do not describe either as
completed without new evidence.

Also deferred: playback update/correction/delete simulation. If revisited,
retain immutable raw events and apply corrections to derived effective tables.

## Architectural intent from history

The 2022 upstream project used GCP, Dataproc/GCS/BigQuery, Airflow, and dbt. The
2026 fork deliberately moved to self-managed Azure VMs, open-source Spark,
ADLS Gen2, and Snowflake while retaining the original educational structure.

Recent history favors:

- explicit infrastructure over managed Spark services;
- a small topology close to upstream;
- clear separation of Azure, Snowflake, Airflow, dbt, and Polaris setup;
- bilingual deployment docs without duplicated troubleshooting notes;
- manual, inspectable steps before automation;
- keeping speculative Iceberg work separate from the verified Parquet path.

The original GCP architecture image remains only as a historical comparison.
Do not use it as the current architecture specification.
