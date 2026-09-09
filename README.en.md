# Streamify Azure Snowflake

[中文](README.md) | English

This is an independent adaptation of the [original Streamify project](https://github.com/ankurchavda/streamify), with the upstream Git history and authorship preserved. It rebuilds the pipeline on Azure and uses Snowflake instead of BigQuery as the warehouse.
Kafka, open-source Spark, and Airflow run in Docker on Azure VMs. Terraform manages the infrastructure.

## What it does

[Eventsim](https://github.com/Interana/eventsim) generates listening, page-view, and login events for a simulated music website.
The original pipeline sends events through Kafka, writes them to the data lake with Spark every two minutes, and runs hourly dbt transformations to build dimension and fact tables for song popularity, active-user, and demographic analysis.

Eventsim uses the [10,000-song subset](http://millionsongdataset.com/pages/getting-dataset/#subset) of the [Million Song Dataset](http://millionsongdataset.com). The retained Eventsim Docker build comes from [viirya's fork](https://github.com/viirya/eventsim).

## Migration status

- Terraform has been adapted to Azure: five VMs, networking, and ADLS Gen2.
- Kafka and Eventsim have updated private-address configuration, memory settings, and installation scripts.
- Spark standalone cluster and ADLS Gen2 streaming output are adapted. Airflow DAGs, dbt SQL, and the Snowflake connection are not complete.

Planned pipeline:

```text
Eventsim → Kafka → Spark → ADLS Gen2 → Snowflake → dbt models → BI
                                      ↑
                         Airflow schedules loading and transformation
```

dbt submits transformation SQL to Snowflake. This is the target architecture, not a claim that the full pipeline is already running.

## Setup order

1. [Azure account and access](setup/azure.en.md)
2. [Install and use Terraform](setup/terraform.en.md)
3. [SSH access and port forwarding](setup/ssh.en.md)
4. [Kafka and Eventsim](setup/kafka.en.md)
5. [Spark standalone cluster](setup/spark.en.md)

Documentation uses placeholders. Keep actual IPs, subscription details, and keys in your local configuration, out of the repository.

## Original project reference

This is the original GCP architecture diagram; it has not yet been replaced with an Azure version:

![Original Streamify GCP architecture](images/Streamify-Architecture.jpg)

The original project's dashboard example:

![Original project dashboard](images/dashboard.png)

These guides still describe the GCP version and should not be followed as Azure deployment instructions:

- [GCP setup](setup/gcp.md)
- [Airflow setup](setup/airflow.md)
- [Debugging](setup/debug.md)
- [Original video walkthrough](https://youtu.be/vzoYhI8KTlY)

The original project also suggested incremental models, data quality tests, more dimensional models, CI/CD, and additional visualizations. Those changes are outside the current migration scope.

Thanks to the original author and [DataTalks.Club Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp) for the project and course materials.
