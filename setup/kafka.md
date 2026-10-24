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

首次启动前，在项目根目录创建 Kafka 的本地 Compose 配置，并把占位符替换为 Kafka VM 的实际私网 IP。查询方法见 [SSH 文档](ssh.md)：

```bash
cp kafka/.env.example kafka/.env
docker compose -f kafka/docker-compose.yml up -d
docker compose -f kafka/docker-compose.yml ps
```

Docker Compose 会自动读取 `kafka/.env`，以后启动 Kafka 不必再手动 `export KAFKA_ADDRESS`。
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
cp eventsim/.env.example eventsim/.env
bash scripts/eventsim_startup.sh build
bash scripts/eventsim_startup.sh start
docker logs --follow million_events
```

`build` 使用 `eventsim/Dockerfile` 构建 `events:1.0`；`start` 使用现有镜像创建容器，不传参数时默认 `start`。已有 `.env` 时直接编辑，不重复复制。
Eventsim 使用 host 网络，默认连接同机的 `localhost:9092`。
Java 堆上限为 4 GB，容器内存上限为 5.5 GB。100 万用户、持续生成 24 小时等参数沿用原项目。

`eventsim/.env` 提供运行参数：`EVENTSIM_KAFKA_BOOTSTRAP_SERVERS` 是完整的 broker 地址列表，`EVENTSIM_USERS` 是模拟用户数，`EVENTSIM_DURATION_DAYS` 是模拟时间跨度，`EVENTSIM_GROWTH_RATE`、`EVENTSIM_USER_ID`、`EVENTSIM_RANDOM_SEED` 分别设置增长率、起始用户 ID 和随机种子。`EVENTSIM_CONFIG` 是容器内 JSON 配置路径，默认 `examples/example-config.json`。原有默认参数和手动启动方式保持不变。

宿主机的 `eventsim/examples/` 只读挂载到容器 `/opt/eventsim/examples/`。修改 JSON 不必重新构建镜像，重新运行生成器时读取新内容。环境参数属于容器创建参数；修改 `.env` 后，需停止并删除旧的 `million_events` 容器，再运行 `start` 创建新容器。删除会丢弃生成器当前进度，但不删除 Kafka broker 的数据。仅用 `docker start million_events` 会复用旧参数。修改 Dockerfile、JAR 或镜像内脚本时才重新 `build`。

脚本用于首次创建容器。若 `million_events` 已存在，先检查状态，不要重复创建：

```bash
docker ps -a --filter name=million_events
```

已停止的原容器可用 `docker start million_events` 启动，仍使用创建时的参数和镜像。
启动后应出现 `listen_events`、`page_view_events`、`auth_events` 和 `status_change_events` 四个 Topic。

参考：[Docker Ubuntu 安装说明](https://docs.docker.com/engine/install/ubuntu/)、[Compose 环境变量插值](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/)
