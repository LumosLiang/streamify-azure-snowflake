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

`.env` 已被 Git 忽略，不要提交。`POLARIS_CLIENT_ID` 和 `POLARIS_CLIENT_SECRET` 是初始 root principal 的凭据，需要保存。

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

将输出中的 `tenant`、`appId`、`password` 分别填入 Spark Master VM 上 `polaris/.env` 的 `AZURE_TENANT_ID`、`AZURE_CLIENT_ID`、`AZURE_CLIENT_SECRET`。不要把输出或 `.env` 提交到 Git。Polaris 使用这组凭据获取存储访问权限，之后才能为表客户端签发短期访问凭据。

## 4. 启动并检查服务

```bash
docker compose up -d
docker compose ps
docker compose logs bootstrap
curl http://localhost:8182/q/health
```

`bootstrap` 首次创建 `POLARIS` realm 后正常退出；PostgreSQL 和 Polaris 会继续运行。API 使用端口 `8181`，管理和健康检查使用 `8182`。
健康检查只证明服务已启动；ADLS 访问要在创建 catalog 和表后验证。

以后查看和停止服务：

```bash
docker compose logs --follow polaris
docker compose down
```

不要使用 `docker compose down -v`，它会删除 PostgreSQL volume 中的 Polaris metadata。

参考：[Polaris 的 Azure 存储配置](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/)。
