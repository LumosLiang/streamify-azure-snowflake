# Snowflake 初始化

中文 | [English](snowflake_setup.en.md)

本阶段只创建 dbt 连接所需的 user、role、warehouse、database 和 schemas。dbt 使用专用的 `SERVICE` user 和 RSA key pair，不使用密码。

## 1. 在 Airflow VM 生成密钥

```bash
cd ~/streamify
mkdir -p airflow/secrets
chmod 700 airflow/secrets

openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc \
  -inform PEM -out airflow/secrets/snowflake_rsa_key.p8

openssl rsa -in airflow/secrets/snowflake_rsa_key.p8 -pubout \
  -out airflow/secrets/snowflake_rsa_key.pub

chmod 600 airflow/secrets/snowflake_rsa_key.p8
```

第一条命令会要求设置 private-key passphrase。私钥和 passphrase 都不能提交到 Git。

复制 Snowflake SQL 需要的单行公钥内容：

```bash
grep -v '^-----' airflow/secrets/snowflake_rsa_key.pub | tr -d '\n'
```

## 2. 初始化 Snowflake

打开 Snowsight worksheet，使用有权创建 account objects 的管理员角色。打开 `airflow/snowflake_setup.sql`，把 `<snowflake-public-key-body>` 替换成上一步输出，然后执行整个文件。

它创建：

- user：`STREAMIFY_DBT`
- role：`STREAMIFY_TRANSFORMER`
- warehouse：`STREAMIFY_TRANSFORM_WH`，X-Small，空闲 60 秒自动暂停
- database：`STREAMIFY`
- schemas：`STREAMIFY_STG` 和 `STREAMIFY_PROD`

脚本最后的 `ADD KEY PAIR` 只需执行一次；重复执行整个文件时跳过最后一条语句。

## 3. 配置 Airflow VM

```bash
cp airflow/.env.example airflow/.env
```

填写 `SNOWFLAKE_ACCOUNT`，并把生成私钥时设置的 passphrase 写入 `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`。其余 Snowflake 值已经与 SQL 对齐。

按照 [Airflow setup](../setup/airflow.md) 构建镜像，再按照 [dbt setup](../setup/dbt.md) 执行 `dbt debug`。

