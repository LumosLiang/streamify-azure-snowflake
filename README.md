# Streamify Azure Snowflake

中文 | [English](README.en.md)

这是基于[原始 Streamify 项目](https://github.com/ankurchavda/streamify)的独立改造版本，保留了上游 Git 历史和作者信息。项目模拟音乐网站事件，把持续产生的数据写入数据湖，再加载到 Snowflake 建模。

## 架构

```text
Eventsim → Kafka → Spark Structured Streaming → ADLS Gen2（Parquet）
                 └→ Spark Structured Streaming → Polaris → ADLS Gen2（Iceberg）
ADLS Gen2（Parquet）→ Snowflake staging → dbt 模型
Snowflake 查询 → Polaris catalog → ADLS Gen2（Iceberg）
Airflow 调度 Snowflake COPY/dbt；Iceberg 维护 DAG 配置为每日运行
```

Terraform 在 Azure 创建五台 VM、网络和 ADLS Gen2：一台运行 Kafka 与 Eventsim 容器，一台运行 Airflow 容器，另外三台直接安装开源 Spark，组成一个 master、两个 worker 的 standalone 集群。Snowflake 位于 AWS，通过 Azure storage integration 读取 ADLS 中的 Parquet；Airflow 每小时运行 `COPY INTO` 和 dbt。当前 dbt 核心模型主要使用听歌事件，页面浏览和登录事件已入仓，但尚未用于这些模型。项目没有部署 BI 仪表盘。

Polaris 管理的 Iceberg 表已接入 `listen_events` 流式写入，Snowflake 查询该表已通过验证。Airflow 的 Iceberg 维护 DAG 已配置为每日执行小文件合并和七天快照过期，但快照过期与 Airflow 运行结果仍待验证，首次创建时 DAG 为暂停状态。Iceberg writer 是独立的长时间运行 Spark 作业，不由维护 DAG 启停。

Eventsim 使用 [Million Song Dataset 的 10,000 首歌曲子集](http://millionsongdataset.com/pages/getting-dataset/#subset)，其 Docker 构建来自 [viirya 的分支](https://github.com/viirya/eventsim)。

## 部署文档

本地阅读、调试和测试 Python 代码，先按 [本地开发环境](setup/development.md) 创建 uv 环境。

按顺序阅读 [Azure 账号与权限](setup/azure.md)、[Terraform](setup/terraform.md)、[SSH](setup/ssh.md)、[Kafka 与 Eventsim](setup/kafka.md)、[Spark](setup/spark.md)、[Snowflake](snowflake/README.md)、[Airflow](setup/airflow.md) 和 [dbt](setup/dbt.md)。Polaris 与 Iceberg 配置见 [Polaris](setup/polaris.md)。配置示例统一使用占位符。

## 原项目参考图片

下面是原项目的 GCP 架构图，用于对照改造前的链路；其中的 GCS、BigQuery 和 Data Studio 不属于当前部署。

![原项目 GCP 架构](images/Streamify-Architecture.jpg)

下面是原项目的仪表盘示例；当前项目尚未部署仪表盘。

![原项目仪表盘示例](images/dashboard.png)
