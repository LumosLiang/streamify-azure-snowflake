# Streamify Azure Snowflake

[中文](README.md) | English

This is an independent adaptation of the [original Streamify project](https://github.com/ankurchavda/streamify), with its Git history and authorship preserved. It generates events for a simulated music website, writes them to a data lake, and loads them into Snowflake for modeling.

## Architecture

```text
Eventsim → Kafka → Spark Structured Streaming → ADLS Gen2 (Parquet)
                                             ↓
                            Snowflake staging → dbt models
                                    ↑
                           Airflow schedules load and modeling
```

Terraform creates five Azure VMs, networking, and ADLS Gen2: one VM runs Kafka and Eventsim containers, one runs Airflow containers, and three run open-source Spark installed directly on the VMs as a standalone master and two workers. Snowflake runs on AWS and reads Parquet from ADLS through an Azure storage integration. Airflow runs `COPY INTO` and dbt hourly. The current core dbt models mainly use listening events; page-view and authentication events are loaded but are not yet used by those models. This project does not deploy a BI dashboard.

Polaris has been validated with one Iceberg table created through Spark SQL in a separate ADLS Gen2 Storage Account. It is not yet part of the streaming path above.

Eventsim uses the [10,000-song subset of the Million Song Dataset](http://millionsongdataset.com/pages/getting-dataset/#subset). Its Docker build comes from [viirya's fork](https://github.com/viirya/eventsim).

## Deployment guides

Read [Azure account and access](setup/azure.en.md), [Terraform](setup/terraform.en.md), [SSH](setup/ssh.en.md), [Kafka and Eventsim](setup/kafka.en.md), [Spark](setup/spark.en.md), [Snowflake](snowflake/README.en.md), [Airflow](setup/airflow.en.md), and [dbt](setup/dbt.en.md), in that order. The isolated Iceberg validation environment is covered by the [Polaris guide](setup/polaris.en.md). All examples use placeholders.

## Original project images

This is the original GCP architecture, kept to show the pipeline before the adaptation. Its GCS, BigQuery, and Data Studio components are not part of the current deployment.

![Original GCP architecture](images/Streamify-Architecture.jpg)

This is the original project's dashboard example. This project does not currently deploy a dashboard.

![Original project dashboard example](images/dashboard.png)
