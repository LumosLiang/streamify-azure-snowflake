# Streamify Azure Snowflake

中文 | [English](README.en.md)

这是基于 [原始 Streamify 项目](https://github.com/ankurchavda/streamify) 的独立改造版本，完整保留上游 Git 历史和作者信息。项目在 Azure 上重新实现数据流水线，用 Snowflake 替代 BigQuery 作为数仓。
Kafka、开源 Spark 和 Airflow 使用 Azure VM 与 Docker 部署，基础设施由 Terraform 管理。

## 项目做什么

[Eventsim](https://github.com/Interana/eventsim) 模拟音乐网站的听歌、浏览和登录事件。
原项目通过 Kafka 接收事件，Spark 每两分钟写入数据湖，再按小时用 dbt 生成维度表和事实表，分析热门歌曲、活跃用户和用户分布。

Eventsim 使用 [Million Song Dataset](http://millionsongdataset.com) 的 [10,000 首歌曲子集](http://millionsongdataset.com/pages/getting-dataset/#subset)。随项目保留的 Eventsim Docker 构建来自 [viirya 的分支](https://github.com/viirya/eventsim)。

## 迁移进度

- Terraform 已适配 Azure：五台 VM、必要网络和 ADLS Gen2。
- Kafka 与 Eventsim 已适配私网地址、内存配置和安装脚本。
- Spark standalone 集群和 ADLS Gen2 流写入已适配；Airflow DAG、dbt SQL 和 Snowflake 接入尚未完成。

目标链路：

```text
Eventsim → Kafka → Spark → ADLS Gen2 → Snowflake → dbt 模型 → BI
                                      ↑
                           Airflow 调度加载与转换
```

dbt 把转换 SQL 提交给 Snowflake 执行。上图表示目标架构，不代表整条链路已经跑通。

## 操作顺序

1. [Azure 账号与权限](setup/azure.md)
2. [Terraform 安装与部署](setup/terraform.md)
3. [SSH 连接与端口转发](setup/ssh.md)
4. [Kafka 与 Eventsim](setup/kafka.md)
5. [Spark standalone 集群](setup/spark.md)

文档使用占位符。自己的 IP、订阅信息和密钥只填写到本地配置，不要提交到仓库。

## 原项目参考

下图是原 GCP 架构，尚未替换成 Azure 版本：

![原 Streamify GCP 架构](images/Streamify-Architecture.jpg)

原项目的仪表盘示例：

![原项目仪表盘](images/dashboard.png)

以下文档仍是原 GCP 版本，不要直接作为 Azure 部署步骤：

- [GCP 配置](setup/gcp.md)
- [Airflow 配置](setup/airflow.md)
- [调试说明](setup/debug.md)
- [原作者视频演示](https://youtu.be/vzoYhI8KTlY)

原项目还列出了增量模型、数据质量测试、更多维度模型、CI/CD 和可视化等改进方向；这些不在当前迁移范围内。

感谢原作者和 [DataTalks.Club Data Engineering Zoomcamp](https://github.com/DataTalksClub/data-engineering-zoomcamp) 提供的项目与课程资料。
