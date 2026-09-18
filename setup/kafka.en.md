# Run Kafka and Eventsim on Azure

[中文](kafka.md) | English

Kafka and Eventsim run in separate containers on the same VM. Kafka uses Confluent Platform 7.9.9 in KRaft mode without ZooKeeper. The Kafka Compose file has no persistent volume.

## 1. Prepare the project

Connect from your Mac:

```zsh
ssh streamify-kafka
```

Place the project, including the current changes, on the VM. Run the remaining commands from the **project root on the VM**.
The repository can be in any directory; the startup script finds Eventsim relative to its own location.

## 2. Install Docker and Compose

```bash
bash scripts/vm_setup.sh
```

The script installs Docker Engine and the Compose plugin from Docker's official Ubuntu repository.
Run `exit` and reconnect over SSH to pick up Docker group membership. Return to the project root and check:

```bash
docker --version
docker compose version
```

## 3. Start Kafka

Replace the placeholder with the Kafka VM's private IP. See the [SSH guide](ssh.en.md) for the query command.

```bash
export KAFKA_ADDRESS="<kafka-private-ip>"
docker compose -f kafka/docker-compose.yml up -d
docker compose -f kafka/docker-compose.yml ps
```

Compose requires `KAFKA_ADDRESS` to be set explicitly. Set it in each new terminal before running these commands.
`KAFKA_ADVERTISED_LISTENERS` tells clients which address to use. Containers in the Compose network use `broker:29092`; other VMs use `<kafka-private-ip>:9092`.

Once the broker is ready, list the topics. If this fails, check the container logs first:

```bash
docker compose -f kafka/docker-compose.yml exec broker \
  kafka-topics --bootstrap-server broker:29092 --list
```

See [SSH port forwarding](ssh.en.md) to open Kafka Control Center.

## 4. Start Eventsim

```bash
bash scripts/eventsim_startup.sh
docker logs --follow million_events
```

The script builds `events:1.0` using `eventsim/Dockerfile`, then starts the container.
Eventsim uses host networking and connects to `localhost:9092` on the same VM.
The Java heap limit is 4 GB; the container memory limit is 5.5 GB. The original one-million-user and 24-hour generation settings are unchanged.

The script creates a new container. If `million_events` already exists, check its status before running it again:

```bash
docker ps -a --filter name=million_events
```

Use `docker start million_events` to restart an existing stopped container. It retains the image and arguments used when it was created.
The expected topics are `listen_events`, `page_view_events`, `auth_events`, and `status_change_events`.

Reference: [Install Docker on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
