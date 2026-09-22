# Terraform 安装与部署

中文 | [English](terraform.en.md)

先完成 [Azure 账号与权限准备](azure.md)。以下命令在 **Mac** 上执行，不是在云 VM 上执行。

## 1. 安装 Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

当前 `main.tf` 要求 Terraform **>= 1.16.0 且 < 2.0**，AzureRM provider 固定为 **5.4.0**。

## 2. 填写参数

在项目根目录执行。已有 `terraform.tfvars` 时直接编辑，不要用示例覆盖：

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

| 文件 | 作用 |
| --- | --- |
| `main.tf` | 定义要创建的资源 |
| `variables.tf` | 定义参数、类型和默认值 |
| `terraform.tfvars.example` | 参数填写示例，不会自动加载 |
| `terraform.tfvars` | 实际参数值，覆盖 `variables.tf` 中的默认值 |
| `.terraform.lock.hcl` | 锁定 provider 版本和校验值，提交到 Git |
| `.terraform/` | `init` 下载的本地插件缓存 |

填写这几个值：

| 参数 | 填什么 |
| --- | --- |
| `subscription_id` | Azure Portal 中额度订阅的 Subscription ID |
| `storage_account_name` | 自己起的全球唯一名称，3–24 位小写字母或数字 |
| `admin_object_id` | `az ad signed-in-user show --query id --output tsv` 返回的 Object ID |
| `polaris_service_principal_object_id` | Polaris 存储 service principal 的 Object ID，获取方法见 [Polaris 配置](polaris.md) |
| `admin_source_cidr` | SSH 实际公网出口 IPv4 加 `/32` |
| `ssh_public_key_path` | Mac 上的公钥路径，例如 `~/.ssh/id_ed25519.pub` |
| `location` | `southeastasia`，即新加坡 |

未填写的参数使用 `variables.tf` 中的默认值；没有默认值的参数必须提供。
已有 SSH 公钥可以复用，没有时运行 `ssh-keygen -t ed25519`，不要覆盖已有密钥。
如果使用 VPN，确认 SSH 流量走的是放行的出口；HTTP 代理查询到的 IP 不一定是 SSH 的出口。

## 3. 检查并创建资源

<a id="azure-login"></a>

### Azure 登录

登录并选择额度订阅：

```bash
az login
az account list --output table
az account set --subscription "<subscription-id>"
az account show --output table
```

Terraform 使用这个登录身份，不需要为本机部署另建服务账号或下载密钥。

### Terraform 命令

在 `terraform/` 目录执行：

```bash
terraform init
terraform validate
terraform plan
```

- `init` 下载 provider 并初始化工作目录。
- `validate` 检查配置是否合法。
- `plan` 连接 Azure，预览将创建、修改或删除的资源；不会创建 VM。

确认计划符合预期后，再执行：

```bash
terraform apply
```

`apply` 会再次展示计划，需要输入 `yes` 确认。资源创建后开始计费。

## 4. 默认资源

| 资源 | 当前配置 |
| --- | --- |
| Kafka VM | 1 台 D4as v5：4 核、16 GiB |
| Airflow VM | 1 台 E2as v5：2 核、16 GiB |
| Spark master + 两个 worker | 3 台 D2as v5：每台 2 核、8 GiB，Spark 另行安装 |
| 数据湖 | 两个 ADLS Gen2 Storage Account：现有 Parquet 使用 `streamify`；Iceberg 账号包含 `streamify-iceberg` 表 container 和 `streamify-checkpoints` 流状态 container |
| Snowflake | Terraform 不创建；在现有 AWS 账号中按 [Snowflake 初始化](../snowflake/README.md) 配置 |

Kafka VM 使用 Ubuntu 24.04 和 62 GiB Standard SSD 系统盘；其余四台 VM 使用 32 GiB。
网络资源包括 Resource Group、VNet、Subnet、NSG、网卡和公网 IP。
SSH 只允许 `admin_source_cidr` 指定的地址，VM 之间用私网 IP 通信。

Terraform 只创建基础设施，不安装 Docker 或启动应用，也没有自动关机。
部署完成后，按 [SSH 配置](ssh.md) 连接 VM，再按 [Kafka 与 Eventsim 部署](kafka.md) 安装服务。

当前事件数据和 checkpoint 仍使用 `streamify` 容器，路径为：

```text
abfss://streamify@<account-name>.dfs.core.windows.net/<event-type>/
abfss://streamify@<account-name>.dfs.core.windows.net/checkpoint/<event-type>/
```

`streamify-iceberg` 和 `streamify-checkpoints` 位于独立的 HNS Storage Account。前者仅由 Polaris 管理 Iceberg 表的数据和 metadata；后者仅保存 Spark Structured Streaming 的 checkpoint。账号名由订阅 ID 的哈希确定，并避开会触发 [Azure SDK endpoint 解析问题](../polaris/azure-directory-sas-account-name-bug.md)的服务关键字；它不会改变现有 Parquet 写入路径。

Snowflake 外部 Stage 对应的地址为：

```text
azure://<account-name>.blob.core.windows.net/streamify/
```

当前配置没有自动清理数据；checkpoint 需要保留供流处理作业恢复。

<a id="runtime-identities"></a>

### 运行身份与权限

| 用途 | 身份与权限 | 配置位置 |
| --- | --- | --- |
| 在 Mac 上部署资源 | 你的 Azure 用户及部署权限 | Azure CLI 登录、订阅 IAM |
| 在 Portal 查看两个账号的数据 | 你的 Azure 用户，Storage Blob Data Reader，账号级作用域 | Terraform 创建 |
| Spark 读写现有 `streamify` 容器 | VM Managed Identity，Storage Blob Data Contributor | Terraform 创建 |
| Airflow 读取现有 `streamify` 容器 | VM Managed Identity，Storage Blob Data Reader | Terraform 创建 |
| Polaris 为 Iceberg 表签发 ADLS SAS | 独立 Azure Service Principal，独立 Iceberg Storage Account 上的 Storage Blob Data Contributor | Terraform 根据 principal Object ID 创建 |
| Spark 写 Iceberg checkpoint | VM Managed Identity，`streamify-checkpoints` 上的 Storage Blob Data Contributor | Terraform 创建 |
| AWS Snowflake 读取 ADLS | Snowflake 对应的 Azure Service Principal | 按 [Snowflake 初始化](../snowflake/README.md) 授权 |

Managed Identity 是 Azure 为 VM 管理的程序身份，不需要手动保存凭据。Terraform 创建身份和权限后，Spark 等程序仍需配置为使用这个身份访问存储。

## 5. State 和后续修改

Azure state 保存在本地 `azure.tfstate`。保留 state，Terraform 才能跟踪已创建的资源。

以后调整规格，修改 `terraform.tfvars` 或默认值，再运行 `terraform plan` 查看影响。计划可能包含停机或替换资源，确认后才执行 `apply`。

## 6. 停机与删除

日常不用时，在 Portal 对五台 VM 执行 Stop，确认状态为 **Stopped (deallocated)**。
也可以用 CLI 逐台解除分配，例如：

```bash
az vm deallocate --resource-group "<resource-group>" --name "<vm-name>"
```

解除分配停止计算计费，磁盘、公网 IP 和 ADLS 仍计费。本配置没有自动关机。

脚本只启动或停止当前 Azure CLI 订阅中 `streamify-rg` 下、本项目定义的 **五台 VM**：Kafka、Airflow、Spark Master 和两个 Worker，不会处理其他 VM。在 Mac 的项目根目录运行：

```bash
# 先查看订阅和目标，不执行关机
bash scripts/bulk_operate_vm.sh stop --dry-run

# 确认范围后，停止并解除分配
bash scripts/bulk_operate_vm.sh stop

# 启动五台 VM
bash scripts/bulk_operate_vm.sh start
```

`start` 和 `stop` 均支持 `--dry-run`；必须显式指定操作。启动仅检查 VM 运行状态，不代表 Docker 内的服务已就绪。

脚本逐台等待完成并检查状态；一台失败会继续处理其他 VM，最后返回失败状态。
目标资源组和五台 VM 的名称与 `terraform/main.tf` 一致。订阅由 `az account set` 选择，脚本不保存账号或 IP。


只有不再需要整套资源时，才在 `terraform/` 目录运行：

```bash
terraform destroy
```

它会删除受此 state 管理的资源及相关数据，不是日常关机命令。

参考：[Terraform 安装](https://developer.hashicorp.com/terraform/install)

- [Terraform 使用 Azure CLI 认证](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)
- [Managed Identity](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
