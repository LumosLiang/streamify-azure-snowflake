# Snowflake 初始化

中文 | [English](snowflake_setup.en.md)

本阶段建立 `ADLS2 → Snowflake staging → dbt` 所需的对象。

## 1. 创建 Snowflake 身份和基础对象

在 Airflow VM 生成加密私钥：

```bash
cd ~/streamify-azure-snowflake
mkdir -p airflow/secrets
chmod 700 airflow/secrets
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc \
  -inform PEM -out airflow/secrets/snowflake_rsa_key.p8
openssl rsa -in airflow/secrets/snowflake_rsa_key.p8 -pubout \
  -out airflow/secrets/snowflake_rsa_key.pub
chmod 600 airflow/secrets/snowflake_rsa_key.p8
grep -v '^-----' airflow/secrets/snowflake_rsa_key.pub | tr -d '\n'
```

在 Snowsight 中打开 `airflow/snowflake_setup.sql`，替换公钥占位符后执行。它创建专用 service user、role、X-Small warehouse、staging/prod schemas 和三个 staging 表。最后的 `ADD KEY PAIR` 只执行一次。

## 2. 允许 Snowflake 读取 ADLS2

取得 tenant ID；storage account name 可在 `terraform/terraform.tfvars` 的 `storage_account_name` 中查看：

```bash
az account show --query tenantId -o tsv
```

在 `airflow/snowflake_storage_setup.sql` 中替换对应占位符，然后先执行到 `DESC STORAGE INTEGRATION`。在结果中：

1. 打开 `AZURE_CONSENT_URL` 并同意授权。
2. 在 Azure Storage Account 的 **Access control (IAM)** 中，把 **Storage Blob Data Reader** 角色授予 `AZURE_MULTI_TENANT_APP_NAME` 对应的企业应用。
3. 回到 Snowsight，执行文件剩余部分。最后的 `LIST` 能看到 Parquet 文件即为成功。

这里使用的地址格式是 `azure://<account>.blob.core.windows.net/streamify/`；ADLS Gen2 也使用这个格式。

## 3. 配置 Airflow

```bash
test -f airflow/.env || cp airflow/.env.example airflow/.env
```

填写 `SNOWFLAKE_ACCOUNT` 和私钥 passphrase。其余值保持默认即可。`airflow/.env` 和私钥均不能提交到 Git。

接着按 [Airflow 安装](../setup/airflow.md) 重建镜像，再按 [dbt 配置](../setup/dbt.md) 验证连接。
