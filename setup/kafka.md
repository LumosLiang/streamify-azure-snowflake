# 在 Azure 上运行 Kafka 和 Eventsim

中文 | [English](kafka.en.md)

Kafka 和 Eventsim 在同一台 VM 的独立容器中运行。Kafka 使用 Confluent Platform 7.9.9 的 KRaft 模式，不依赖 ZooKeeper。Kafka Compose 没有配置持久卷。

为避免持续生成事件耗尽 VM 磁盘，所有 Kafka Compose 容器和 Eventsim 都使用 Docker `local` 日志驱动，每个容器最多保留 3 个 100 MiB 日志文件。Broker 默认最多保留 24 小时、每 partition 最多 512 MiB 的消息；128 MiB segment 让过期段能够及时删除。

## 1. 准备项目

在 Mac 上登录：

```zsh
ssh streamify-kafka
```

将包含当前修改的项目放到 VM。后续命令在 **VM 的项目根目录**执行。
项目可以放在任意目录，启动脚本会根据自身位置找到 Eventsim。

## 2. 安装 Docker 和 Compose

```bash
bash scripts/vm_setup.sh
```

脚本使用 Docker 官方 Ubuntu 软件源安装 Docker Engine 和 Compose 插件。
完成后执行 `exit`，重新 SSH 登录，让 Docker 用户组权限生效。返回项目根目录检查：

```bash
docker --version
docker compose version
```

## 3. 启动 Kafka

将占位符替换为 Kafka VM 的实际私网 IP。查询方法见 [SSH 文档](ssh.md)。

```bash
export KAFKA_ADDRESS="<kafka-private-ip>"
docker compose -f kafka/docker-compose.yml up -d
docker compose -f kafka/docker-compose.yml ps
```

Compose 要求明确设置 `KAFKA_ADDRESS`。每次在新终端运行这些命令前，都要设置该变量。
`KAFKA_ADVERTISED_LISTENERS` 会把地址告知客户端；Docker 内部组件使用 `broker:29092`，其他 VM 使用 `<kafka-private-ip>:9092`。

等待 Broker 就绪后检查 Topic；如果失败，先查看容器日志：

```bash
docker compose -f kafka/docker-compose.yml exec broker \
  kafka-topics --bootstrap-server broker:29092 --list
```

Kafka Control Center 的访问方法见 [SSH 端口转发](ssh.md)。

### Topic 并行度

事件 topic 默认使用 4 个 partition，与当前 Spark 集群的 4 个 worker core 对齐。一个 partition 在单个 micro-batch 中只能由一个 Kafka 读取 task 消费；增加 Spark Worker 前，应先增加对应 topic 的 partition。

已存在的 topic 不会因 `KAFKA_NUM_PARTITIONS` 自动改变。在线扩容 `listen_events` 时执行：

```bash
docker compose -f kafka/docker-compose.yml exec broker \
  kafka-topics --bootstrap-server broker:29092 \
  --alter --topic listen_events --partitions 4
```

该操作保留已有数据，但 partition 数只能增加，不能减少。新消息会写入新 partition；如果需要按用户保持顺序，生产端应使用用户标识作为 Kafka key。

## 4. 启动 Eventsim

```bash
bash scripts/eventsim_startup.sh
docker logs --follow million_events
```

脚本先使用 `eventsim/Dockerfile` 构建 `events:1.0`，再启动容器。
Eventsim 使用 host 网络，连接同机的 `localhost:9092`。
Java 堆上限为 4 GB，容器内存上限为 5.5 GB。100 万用户、持续生成 24 小时等参数沿用原项目。

脚本用于首次创建容器。若 `million_events` 已存在，先检查状态，不要重复创建：

```bash
docker ps -a --filter name=million_events
```

已停止的原容器可用 `docker start million_events` 启动，仍使用创建时的参数和镜像。
启动后应出现 `listen_events`、`page_view_events`、`auth_events` 和 `status_change_events` 四个 Topic。

参考：[Docker Ubuntu 安装说明](https://docs.docker.com/engine/install/ubuntu/)
