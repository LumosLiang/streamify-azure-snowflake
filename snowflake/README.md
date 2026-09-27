# Snowflake 初始化

中文 | [English](README.en.md)

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

在 Snowsight 中打开 `snowflake/setup.sql`，替换公钥占位符后执行。它创建专用 service user、role、X-Small warehouse、staging/prod schemas 和三个 staging 表。最后的 `ADD KEY PAIR` 只执行一次。

## 2. 允许 Snowflake 读取 ADLS2

取得 tenant ID；storage account name 可在 `terraform/terraform.tfvars` 的 `storage_account_name` 中查看：

```bash
az account show --query tenantId -o tsv
```

在 `snowflake/storage_setup.sql` 中替换对应占位符，然后先执行到 `DESC STORAGE INTEGRATION`。在结果中：

1. 打开 `AZURE_CONSENT_URL` 并同意授权。
2. 在 Azure Storage Account 的 **Access control (IAM)** 中，把 **Storage Blob Data Reader** 角色授予 `AZURE_MULTI_TENANT_APP_NAME` 对应的企业应用。
3. 回到 Snowsight，执行文件剩余部分。最后的 `LIST` 能看到 Parquet 文件即为成功。

这里使用的地址格式是 `azure://<account>.blob.core.windows.net/streamify/`；ADLS Gen2 也使用这个格式。

## 3. 配置 Airflow

```bash
test -f airflow/.env || cp airflow/.env.example airflow/.env
```

填写 `SNOWFLAKE_ACCOUNT` 和私钥 passphrase，其余值保持默认即可。

接着按 [Airflow 安装](../setup/airflow.md) 构建镜像，再按 [dbt 配置](../setup/dbt.md) 验证连接。

## 4. 连接 Polaris 管理的 Iceberg 表

现有 `STREAMIFY_AZURE_INT` 只供 Snowflake 读取 Parquet staging 文件。本项目的 Iceberg 表由另一套 Polaris catalog 管理；Snowflake 使用 `CATALOG_SOURCE = POLARIS` 的 catalog integration 访问自建 Polaris，再从 Polaris 获取短期只读 SAS 访问 ADLS 文件。因此这条链路不复用 Parquet 的 storage integration。

执行 [polaris_catalog_setup.sql](polaris_catalog_setup.sql) 前，有两个前置步骤需要你完成：

1. 让 Polaris REST API 有一个 Snowflake 可访问的 HTTPS 地址。当前运行中的服务仍只有本机/内网 HTTP；Terraform 和 Compose 已准备好 Azure DNS label、Caddy HTTPS 代理和 TCP 443 入口，需按 [Polaris 配置](../setup/polaris.md)检查 plan、由你 apply，并在 Spark Master 配置主机名后启动代理。`localhost`、私网 IP 和 `http://` 地址都不能填进 integration。Terraform 规则会让公网来源可访问 Spark Master 的 443；Polaris API 仍要求 OAuth 认证，8181/8182 仍由 NSG 阻止公网访问。
2. 按 [Polaris 配置第 6 节](../setup/polaris.md#6-创建客户端-principal)运行 `snowflake-reader` 配置，为整个 catalog 创建独立只读 principal。无需传 namespace；不要复用 Spark 的写入 principal。脚本生成的 principal role 名称要与下方 SQL 的 `OAUTH_ALLOWED_SCOPES` 对应。

脚本成功后，把输出的 client ID、client secret、principal role 名称填入 SQL 文件对应的 Polaris 占位符；不要保存到 Spark principal 的配置中。完成前置步骤后，在 SQL 文件里替换 Polaris HTTPS 主机名和 catalog 名，再由 `ACCOUNTADMIN` 在 Snowsight 执行。`SYSTEM$VERIFY_CATALOG_INTEGRATION` 验证 Snowflake 到 Polaris 的认证和 metadata 访问；linked database 会发现整个 catalog 下的 namespace，最后的查询验证 Snowflake 是否能读取 `listen_events`。SQL 尚未执行，端到端结果待验证。

官方参考：[Snowflake Polaris catalog integration 配置](https://docs.snowflake.com/en/user-guide/tables-iceberg-configure-catalog-integration-open-catalog)、[Polaris CLI](https://polaris.apache.org/releases/1.7.0/command-line-interface/)、[Polaris RBAC](https://polaris.apache.org/releases/1.7.0/managing-security/access-control/)、[vended credentials](https://docs.snowflake.com/en/user-guide/tables-iceberg-configure-catalog-integration-vended-credentials)、[catalog-linked database](https://docs.snowflake.com/en/user-guide/tables-iceberg-catalog-linked-database)。
