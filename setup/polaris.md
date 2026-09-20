# 在 Spark Master 上安装 Polaris 和 PostgreSQL

中文 | [English](polaris.en.md)

Polaris 和它的 PostgreSQL metadata database 运行在 Spark Master VM 的 Docker 容器中。本阶段配置 Polaris 访问 ADLS Gen2；尚不创建 Iceberg catalog 或表。

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

Polaris 使用单独的 Azure service principal 访问存储；它与 Polaris 的 root principal 不是同一个身份。在 Mac 上先确认 Azure CLI 选中了部署订阅，然后查询 Storage Account 的资源 ID：

```bash
az storage account show --resource-group streamify-rg \
  --name "<storage-account-name>" --query id --output tsv
```

首次创建 service principal，并在该 Storage Account 上授予 `Storage Blob Data Contributor`：

```bash
az ad sp create-for-rbac --name streamify-polaris-storage \
  --role "Storage Blob Data Contributor" \
  --scopes "<storage-account-resource-id>"
```

`.env.example` 已包含下面三项；如果 Spark Master 上的 `.env` 是之前创建的，在文件末尾补上它们：

```bash
AZURE_TENANT_ID=<tenant>
AZURE_CLIENT_ID=<appId>
AZURE_CLIENT_SECRET=<password>
```

它们分别来自命令输出的 `tenant`、`appId`、`password`。Docker Compose 会把这些值传给 Polaris；后续创建 Azure catalog 时，Polaris 通过 Azure SDK 的 `DefaultAzureCredential` 使用这组 service principal 凭据访问 ADLS，并向表客户端签发短期 SAS token。

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

这一步不创建 namespace 或 Iceberg 表。若 catalog 已存在，脚本会退出，不会覆盖现有配置。

## 6. 查看和停止服务

```bash
docker compose logs --follow polaris
docker compose down
```

不要使用 `docker compose down -v`，它会删除 PostgreSQL volume 中的 Polaris metadata。

参考：[Polaris 的 Azure 存储配置](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/)。
