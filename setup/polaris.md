# 在 Spark Master 上安装 Polaris 和 PostgreSQL

中文 | [English](polaris.en.md)

Polaris 和它的 PostgreSQL metadata database 运行在 Spark Master VM 的 Docker 容器中。本指南完成 Polaris 的 ADLS Gen2 访问、Azure catalog、Spark client 身份和第一张隔离的 Iceberg 验证表；它不改现有的 Parquet streaming 链路。

## 1. 准备 VM

```bash
ssh streamify-spark
cd ~/streamify-azure-snowflake
bash scripts/vm_setup.sh
```

如果刚安装 Docker，退出并重新登录后再继续。

## 2. 创建本地配置

```bash
cd ~/streamify-azure-snowflake/polaris
cp .env.example .env
```

编辑 `.env`，为三个 `POLARIS_` 变量设置不同的随机值：

```bash
openssl rand -hex 24
```

`POLARIS_CLIENT_ID` 和 `POLARIS_CLIENT_SECRET` 是初始 root principal 的凭据。

## 3. 配置 ADLS 访问身份

Polaris 使用单独的 Azure service principal 访问存储；它与 Polaris 的 root principal 不是同一个身份。首次创建该身份：

```bash
az ad sp create-for-rbac \
  --name streamify-polaris-storage
```

用返回的 `appId` 查询 service principal Object ID：

```bash
az ad sp show --id "<appId>" --query id --output tsv
```

把它填入 `terraform.tfvars` 的 `polaris_service_principal_object_id`。Terraform 会在独立 Iceberg Storage Account 上授予 `Storage Blob Data Contributor`。

`.env.example` 已包含下面三项；如果 Spark Master 上的 `.env` 是之前创建的，在文件末尾补上它们：

```bash
AZURE_TENANT_ID=<tenant>
AZURE_CLIENT_ID=<appId>
AZURE_CLIENT_SECRET=<password>
```

它们分别来自创建命令输出的 `tenant`、`appId`、`password`。Docker Compose 会把这些值传给 Polaris；后续创建 Azure catalog 时，Polaris 通过 Azure SDK 的 `DefaultAzureCredential` 使用这组 service principal 凭据访问 ADLS，并向表客户端签发短期 SAS token。

## 4. 启动并检查服务

```bash
docker compose up -d
docker compose ps
docker compose logs bootstrap
curl http://localhost:8182/q/health
```

`bootstrap` 首次创建 `POLARIS` realm 后正常退出；PostgreSQL 和 Polaris 会继续运行。API 使用端口 `8181`，管理和健康检查使用 `8182`。
健康检查只证明服务已启动；ADLS 访问要在创建 catalog 和表后验证。

## 5. 创建 Azure catalog

在 Spark Master 的 `polaris/` 目录运行：

```bash
bash create_catalog.sh \
  <storage-account-name> \
  <container-name> \
  <catalog-name> \
  <base-path>
```

例如，当前独立 Iceberg container 的命名可以是：

```bash
bash create_catalog.sh \
  <storage-account-name> \
  streamify-iceberg \
  streamify_iceberg \
  lake
```

脚本使用 `.env` 中的 Polaris root principal 和 Azure service principal。四个参数分别对应 Azure Storage Account、Azure container、Polaris catalog 名和 container 内的表根路径。container 和 catalog 名没有绑定关系；`lake` 也可以替换为 `warehouse` 或 `lake/raw`。

上例的默认表路径是：

```text
abfss://streamify-iceberg@<storage-account-name>.dfs.core.windows.net/lake/
```

脚本同时启用 catalog 的 namespace custom location。Spark 会把 `validation` namespace 放在默认根路径下的 `lake/validation/`；没有这个属性时，Polaris 会拒绝该路径。

这一步不创建 namespace 或 Iceberg 表。若 catalog 已存在，脚本会退出，不会覆盖现有配置。

## 6. 创建 Spark principal

Spark 不使用 Polaris root principal。它需要自己的 principal、principal role 和 catalog role；脚本把三者关联，并为该 catalog 授予 `CATALOG_MANAGE_CONTENT`，即建表、读取和写入权限。

先在 Spark Master 安装 Polaris CLI：

```bash
sudo apt-get update
sudo apt-get install -y pipx
pipx install apache-polaris
"$HOME/.local/bin/polaris" --version
```

然后在 `polaris/` 目录运行：

```bash
bash create_spark_principal.sh \
  <catalog-name> \
  <principal-name> \
  <principal-role-name> \
  <catalog-role-name>
```

按上一步的 catalog 示例，四个参数可以这样填写：

```bash
bash create_spark_principal.sh \
  streamify_iceberg \
  spark_client \
  spark_principal_role \
  spark_catalog_role
```

第一个参数必须是已经创建的 Polaris catalog。后三个是我们为 Spark 自己命名的授权对象：`spark_client` 是 Spark 登录 Polaris 时使用的 principal，`spark_principal_role` 代表这个 principal 的权限集合，`spark_catalog_role` 则是 catalog 内的角色。脚本会把它们连成下面的关系，并把建表、读表和写表权限授予 catalog role：

```text
spark_client → spark_principal_role → spark_catalog_role → CATALOG_MANAGE_CONTENT
```

脚本先确认 catalog 存在，并拒绝覆盖同名 principal 或角色。成功时会打印下一步需要的 `clientId` 和 `clientSecret`。在 Spark Master 将它们持久化到 `~/.polaris_spark.env`：

```bash
cat > "$HOME/.polaris_spark.env" <<'EOF'
export POLARIS_SPARK_CLIENT_ID=<clientId>
export POLARIS_SPARK_CLIENT_SECRET=<clientSecret>
EOF
```

这个文件保存所有 Spark 客户端共用的 Polaris principal；`spark-iceberg.env` 会加载它。`polaris/.env` 仍只配置 Polaris 服务及其 Azure 存储身份。

## 7. 用 Spark SQL 验证第一张 Iceberg 表

在 Spark Master 的 `polaris/` 目录，先加载 Spark 环境变量和 Spark principal 凭据：

```bash
source "$HOME/.config/streamify/spark-iceberg.env"
```

这条 `SPARK_MASTER_URL` 命令在 Spark Master 上取它的私网 IP，组成 standalone Master URL。然后自己启动交互式 Spark SQL。将 `<catalog-name>` 替换为 Polaris 中已有的 Azure catalog：

```bash
"$SPARK_HOME/bin/spark-sql" \
  --master "$SPARK_MASTER_URL" \
  --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0,org.apache.iceberg:iceberg-azure-bundle:1.11.0 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.polaris.type=rest \
  --conf spark.sql.catalog.polaris.uri=http://127.0.0.1:8181/api/catalog \
  --conf spark.sql.catalog.polaris.oauth2-server-uri=http://127.0.0.1:8181/api/catalog/v1/oauth/tokens \
  --conf spark.sql.catalog.polaris.token-refresh-enabled=false \
  --conf spark.sql.catalog.polaris.warehouse=<catalog-name> \
  --conf spark.sql.catalog.polaris.scope=PRINCIPAL_ROLE:ALL \
  --conf spark.sql.catalog.polaris.credential="${POLARIS_SPARK_CLIENT_ID}:${POLARIS_SPARK_CLIENT_SECRET}" \
  --conf spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation=vended-credentials \
  --conf spark.sql.catalog.polaris.io-impl=org.apache.iceberg.azure.adlsv2.ADLSFileIO
```

这里的 `polaris` 是本次 Spark session 中的本地 catalog 别名；`<catalog-name>` 才是 Polaris 中已有的 Azure catalog。`--packages` 加入 Spark 4.1 对应的 Iceberg 1.11 runtime 与 Azure bundle；其余 `spark.sql.catalog.polaris.*` 参数依次定义 REST catalog、OAuth 认证、catalog 选择和 ADLS FileIO。Polaris 在建表和加载表时向 Spark 下发短期 ADLS SAS token，因此 Spark 不需要配置静态 Azure 存储凭据。

进入 `spark-sql` prompt 后，打开 `validate_iceberg.sql`，逐条执行其中的 SQL。它会在 `polaris.validation` namespace 中创建 `spark_connectivity` 表、只在缺少时写入一行测试数据，并查询结果。

成功时查询结果包含：

```text
1  polaris-iceberg
```

这一步只会在独立的 Iceberg container 下创建测试数据，不读取或替换现有的 Kafka、Spark Streaming 或 Parquet 输出。

## 8. 查看和停止服务

```bash
docker compose logs --follow polaris
docker compose down
```

不要使用 `docker compose down -v`，它会删除 PostgreSQL volume 中的 Polaris metadata。

参考：[Polaris 的 Azure 存储配置](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/)、[Polaris 的 Spark 用法](https://polaris.apache.org/releases/1.7.0/getting-started/using-polaris/)、[Iceberg 1.11.0 releases](https://iceberg.apache.org/releases/)。
