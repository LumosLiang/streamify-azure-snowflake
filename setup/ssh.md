# SSH 连接与端口转发

中文 | [English](ssh.en.md)

先按 [Terraform 部署说明](terraform.md) 创建 VM。以下操作在 **Mac** 上执行，示例中的地址和用户名均需自行替换。

## 1. 查看连接信息

用 Azure CLI 查看 VM 的连接信息：

```zsh
az vm list -d --resource-group "<resource-group>" \
  --query '[].{Name:name,User:osProfile.adminUsername,PublicIP:publicIps,PrivateIP:privateIps,State:powerState}' \
  --output table
```

SSH 使用 VM 的公网 IP、Terraform 中的 `admin_username`，以及公钥对应的私钥。
Terraform 已配置公钥，不必重复上传。

## 2. 配置 SSH 别名

打开 `~/.ssh/config`，没有则新建。把下面的占位符换成自己的值，再添加到文件中；已有同名 Host 时修改原条目，不要覆盖其他主机。

```sshconfig
Host streamify-kafka
    HostName <kafka-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-airflow
    HostName <airflow-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-spark streamify-spark-master
    HostName <spark-master-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-spark-worker-1
    HostName <spark-worker-1-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes

Host streamify-spark-worker-2
    HostName <spark-worker-2-public-ip>
    User <vm-user>
    IdentityFile ~/.ssh/<private-key-file>
    IdentitiesOnly yes
```

`IdentityFile` 填私钥路径，不是 `.pub` 公钥。替换下面的文件名后设置权限：

```zsh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/config
chmod 600 ~/.ssh/<private-key-file>
```

## 3. 登录

每次选择一条命令执行，进入 VM 后用 `exit` 返回 Mac：

```zsh
ssh streamify-kafka
ssh streamify-airflow
ssh streamify-spark
ssh streamify-spark-worker-1
ssh streamify-spark-worker-2
```

`streamify-spark` 和 `streamify-spark-master` 指向同一台 Spark master。
首次连接时核对主机指纹后再接受。

SSH 的公网出口必须与 `terraform.tfvars` 中的 `admin_source_cidr` 一致。
普通 HTTP 代理不一定接管 SSH；使用 VPN 时，需要确认终端流量的路由。
出口变化后，更新参数并检查 Terraform plan，再决定是否 apply。

## 4. 访问 Web UI

服务启动后，在 Mac 上运行对应的转发命令，再用浏览器打开本机地址。
这些转发只在 SSH 连接存续期间有效，关闭终端或按 `Ctrl+C` 就会结束。

Airflow：

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8080:127.0.0.1:8080 streamify-airflow
```

打开 `http://localhost:8080`。

Spark Master，本机使用 8082 避免与 Airflow 冲突：

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:8082:127.0.0.1:8080 streamify-spark
```

打开 `http://localhost:8082`。

Kafka Control Center：

```zsh
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:9021:127.0.0.1:9021 streamify-kafka
```

打开 `http://localhost:9021`。Broker 的 9092 是消息端口，不是网页。

## 5. 公网与私网地址

Mac 通过公网 IP 登录；Spark 等 VM 之间通过私网 IP 通信，例如 `<kafka-private-ip>:9092`。
保留当前 Static 公网 IP 资源时，普通重启或解除分配不会换公网 IP；删除并重建资源后应重新查询地址。

实际地址和密钥只保存在自己的 SSH 配置中，不写入文档。
