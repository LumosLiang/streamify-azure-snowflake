# 在 Azure VM 上安装 Airflow

中文 | [English](airflow.en.md)

Airflow 运行在独立 VM 的 Docker Compose 中。本阶段只启动 Airflow，不改造或运行原项目 DAG。

## 1. 准备 VM

从 Mac 登录并获取项目：

```bash
ssh streamify-airflow
git clone https://github.com/LumosLiang/streamify-azure-snowflake.git streamify
cd streamify
bash scripts/vm_setup.sh
```

退出后重新登录，使 Docker 用户组权限生效：

```bash
exit
ssh streamify-airflow
cd streamify
```

## 2. 创建本地配置

```bash
cp airflow/.env.example airflow/.env
sed -i "s/^AIRFLOW_UID=.*/AIRFLOW_UID=$(id -u)/" airflow/.env
```

Snowflake 用户和密钥的创建步骤见 [Snowflake 初始化](../airflow/snowflake_setup.md)。编辑 `airflow/.env` 填写 account identifier 和私钥 passphrase。该文件已被 Git 忽略，不要提交。

## 3. 启动并验证

```bash
bash scripts/airflow_startup.sh
cd airflow
docker compose ps
```

启动脚本根据自己的位置查找项目目录，因此仓库放在其他目录时也不需要创建软链接。

按 [SSH 端口转发](ssh.md#4-端口转发) 打开 `http://localhost:8080`。默认用户名和密码均为 `airflow`。

```bash
docker compose logs --follow
docker compose down
```

原始 DAG 仍是 GCP/BigQuery 版本，当前仅保留供阅读，出现 DAG import error 属于预期；适配工作留到后续步骤。
