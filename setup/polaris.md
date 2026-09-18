# 在 Spark Master 上安装 Polaris 和 PostgreSQL

中文 | [English](polaris.en.md)

Polaris 和它的 PostgreSQL metadata database 运行在 Spark Master VM 的 Docker 容器中。本阶段只启动 catalog 服务，不创建 Iceberg catalog 或表。

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

编辑 `.env`，为三个变量设置不同的随机值：

```bash
openssl rand -hex 24
```

`.env` 已被 Git 忽略，不要提交。`POLARIS_CLIENT_ID` 和 `POLARIS_CLIENT_SECRET` 是初始 root principal 的凭据，需要保存。

## 3. 首次启动并验证

```bash
docker compose up -d
docker compose ps
docker compose logs bootstrap
curl http://localhost:8182/q/health
```

`bootstrap` 首次创建 `POLARIS` realm 后正常退出；PostgreSQL 和 Polaris 会继续运行。API 使用端口 `8181`，管理和健康检查使用 `8182`。

以后查看和停止服务：

```bash
docker compose logs --follow polaris
docker compose down
```

不要使用 `docker compose down -v`，它会删除 PostgreSQL volume 中的 Polaris metadata。
