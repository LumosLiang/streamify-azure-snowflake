# 在 Azure VM 上安装 Airflow

中文 | [English](airflow.en.md)

Airflow 运行在独立 VM 的 Docker Compose 中。本阶段只启动 Airflow，不改造或运行原项目 DAG。

## 1. 准备 VM

从 Mac 登录并获取项目：

```bash
ssh streamify-airflow
git clone https://github.com/LumosLiang/streamify-azure-snowflake.git
cd streamify-azure-snowflake
bash scripts/vm_setup.sh
```

退出后重新登录，使 Docker 用户组权限生效：

```bash
exit
ssh streamify-airflow
cd streamify-azure-snowflake
```

## 2. 创建本地配置

```bash
cp airflow/.env.example airflow/.env
sed -i "s/^AIRFLOW_UID=.*/AIRFLOW_UID=$(id -u)/" airflow/.env
```

编辑 `airflow/.env`，填写 Snowflake 连接参数。该文件包含密码，已被 Git 忽略，不要提交。

## 3. 启动并验证

启动脚本需要项目位于 `~/streamify`。当前目录名不同时，先创建链接：

```bash
ln -sfn "$HOME/streamify-azure-snowflake" "$HOME/streamify"
bash scripts/airflow_startup.sh
cd airflow
docker compose ps
```

按 [SSH 端口转发](ssh.md#4-端口转发) 打开 `http://localhost:8080`。默认用户名和密码均为 `airflow`。

```bash
docker compose logs --follow
docker compose down
```

原始 DAG 仍是 GCP/BigQuery 版本，当前仅保留供阅读，出现 DAG import error 属于预期；适配工作留到后续步骤。
