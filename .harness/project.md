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
| Spark | `spark_streaming/`, `scripts/spark_setup.sh`, `setup/spark*.md` | Consume three Kafka topics, normalize records, write partitioned Parquet and checkpoints |
| Snowflake | `snowflake/` | Roles, users, database/schema/warehouse, storage integration, file format and stage |
| Airflow | `airflow/`, `setup/airflow*.md` | Schedule Snowflake loads and dbt commands |
| dbt | `dbt/`, `setup/dbt*.md` | Seeds, dimensions, fact table and wide view |
| Polaris | `polaris/`, `setup/polaris*.md` | Catalog service and PostgreSQL metadata service; catalog and Spark principal are configured, while the Iceberg data path remains deferred |

## Runtime topology and identities

- Kafka VM: Kafka and Eventsim Docker containers.
- Airflow VM: Airflow Docker Compose stack; dbt is installed in the custom
  Airflow image and the repository `dbt/` directory is mounted into containers.
- Spark master and two workers: Spark 4.1.3 installed directly on Ubuntu 24.04.
- Spark VM managed identities have `Storage Blob Data Contributor` on the
  existing `streamify` container.
- Airflow VM managed identity has `Storage Blob Data Reader` on `streamify`.
- The deploying Azure user has account-scoped `Storage Blob Data Reader`, which
  covers both containers.
- Snowflake uses its Azure enterprise application to read the existing container.
- Polaris is designed to use a separate service principal with account-scoped
  `Storage Blob Data Contributor`; catalog/table access has not been validated.

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

These statements describe repository intent plus user-reported results. An agent
must re-check live state before making operational claims.

## Work in progress and deferred decisions

The current Iceberg preparation adds a private `streamify-iceberg` container,
Polaris Azure credentials, one Polaris catalog, and a Spark principal. It does
not yet create a namespace, Iceberg table, Spark Iceberg writer, Snowflake
catalog integration, or Airflow maintenance DAG. Catalog storage access and the
Spark principal remain configured but unverified until Spark creates a table.

Do not implement those later stages as part of a smaller Terraform, RBAC, or
Polaris setup request. The intended sequence is:

1. Create one isolated namespace and Iceberg test table through Spark.
2. Add one parallel Spark Iceberg path without replacing current Parquet output.
3. Evaluate Snowflake access.
4. Add compaction/snapshot/orphan-file maintenance only after the table path is
   understood and approved.

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
