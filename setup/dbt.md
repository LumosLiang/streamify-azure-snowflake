# 配置 dbt 与 Snowflake

中文 | [English](dbt.en.md)

dbt 安装在 Airflow 自定义镜像中。本阶段只建立 Snowflake 连接，不运行或改造原始 models。

## 1. 准备 Snowflake 参数

在 Airflow VM 的项目目录中：

```bash
test -f airflow/.env || cp airflow/.env.example airflow/.env
```

先完成 [Snowflake 初始化](../airflow/snowflake_setup.md)，然后确认以下值：

- `SNOWFLAKE_ACCOUNT`：Snowflake account identifier，例如 `组织名-账号名`
- `SNOWFLAKE_USER`：`STREAMIFY_DBT` service user
- `SNOWFLAKE_PRIVATE_KEY_PATH`：容器中的私钥路径，使用示例默认值
- `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`：生成私钥时设置的 passphrase
- `SNOWFLAKE_ROLE`：dbt 使用的角色
- `SNOWFLAKE_DATABASE`：目标数据库
- `SNOWFLAKE_WAREHOUSE`：执行 SQL 的 warehouse

`dbt/profiles.yml` 从这些环境变量读取连接信息，dev 和 prod 分别使用 `STREAMIFY_STG` 与 `STREAMIFY_PROD` schema。

## 2. 构建并检查

先按 [Airflow 安装](airflow.md) 构建镜像，然后执行：

```bash
cd ~/streamify/airflow
docker compose run --rm airflow-worker dbt --version
docker compose run --rm airflow-worker dbt debug \
  --project-dir /opt/airflow/dbt \
  --profiles-dir /opt/airflow/dbt
```

`dbt debug` 只验证配置和连接。当前原始 models 仍使用 BigQuery SQL，不要运行 `dbt run`。
