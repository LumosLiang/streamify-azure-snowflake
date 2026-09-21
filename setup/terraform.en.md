# Install and use Terraform

[中文](terraform.md) | English

Complete the [Azure account and access setup](azure.en.md) first. Run these commands on your **Mac**, not on a cloud VM.

## 1. Install Terraform

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
terraform version
```

The current `main.tf` requires Terraform **>= 1.16.0 and < 2.0** and pins the AzureRM provider to **5.4.0**.

## 2. Set the variables

From the project root, run the commands below. If `terraform.tfvars` already exists, edit it rather than overwriting it with the example:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

| File | Purpose |
| --- | --- |
| `main.tf` | Defines the resources to create |
| `variables.tf` | Defines variable names, types, and defaults |
| `terraform.tfvars.example` | An example; Terraform does not load it automatically |
| `terraform.tfvars` | Actual values that override defaults from `variables.tf` |
| `.terraform.lock.hcl` | Pins provider versions and checksums; commit it to Git |
| `.terraform/` | Local provider cache downloaded by `init` |

Fill in these values:

| Variable | Value |
| --- | --- |
| `subscription_id` | The credit subscription's Subscription ID from Azure Portal |
| `storage_account_name` | A globally unique name with 3–24 lowercase letters or digits |
| `admin_object_id` | The Object ID returned by `az ad signed-in-user show --query id --output tsv` |
| `polaris_service_principal_object_id` | The Object ID of the Polaris storage service principal; see the [Polaris guide](polaris.en.md) |
| `admin_source_cidr` | The public IPv4 used by your SSH traffic, followed by `/32` |
| `ssh_public_key_path` | Your Mac's public key path, such as `~/.ssh/id_ed25519.pub` |
| `location` | `southeastasia`, which is Singapore |

Unspecified variables use the defaults in `variables.tf`. Variables without defaults must be supplied.
Reuse an existing SSH public key, or run `ssh-keygen -t ed25519` if you need one. Do not overwrite an existing key.
When using a VPN, make sure SSH uses the allowed exit IP. An IP returned through an HTTP proxy may not be the IP used by SSH.

## 3. Check and create resources

<a id="azure-login"></a>

### Azure login

Sign in and select the credit subscription:

```bash
az login
az account list --output table
az account set --subscription "<subscription-id>"
az account show --output table
```

Terraform uses this login. You do not need a separate service account or a downloaded key for local deployment.

### Terraform commands

Run from `terraform/`:

```bash
terraform init
terraform validate
terraform plan
```

- `init` downloads the provider and initializes the working directory.
- `validate` checks the configuration.
- `plan` connects to Azure and previews resource creation, changes, or deletion. It does not create VMs.

After reviewing the plan, run:

```bash
terraform apply
```

`apply` shows the plan again and asks you to enter `yes`. Billing starts as resources are provisioned.

## 4. Default resources

| Resource | Current configuration |
| --- | --- |
| Kafka VM | One D4as v5: 4 vCPUs, 16 GiB |
| Airflow VM | One E2as v5: 2 vCPUs, 16 GiB |
| Spark master and two workers | Three D2as v5 VMs: 2 vCPUs and 8 GiB each; install Spark separately |
| Data lake | Two ADLS Gen2 Storage Accounts: `streamify` for the existing Parquet path and a separate `streamify-iceberg` account |
| Snowflake | Not created by Terraform; configure it in the existing AWS account using [Snowflake setup](../snowflake/README.en.md) |

Each VM uses Ubuntu 24.04 and a 32 GiB Standard SSD OS disk.
Networking includes a resource group, VNet, subnet, NSG, network interfaces, and public IPs.
SSH is restricted to `admin_source_cidr`. VMs communicate through private IPs.

Terraform creates the infrastructure only. It does not install Docker, start applications, or schedule shutdowns.
After deployment, follow the [SSH guide](ssh.en.md), then [deploy Kafka and Eventsim](kafka.en.md).

Current event data and checkpoints remain in the `streamify` container:

```text
abfss://streamify@<account-name>.dfs.core.windows.net/<event-type>/
abfss://streamify@<account-name>.dfs.core.windows.net/checkpoint/<event-type>/
```

`streamify-iceberg` is in a separate HNS-enabled Storage Account. Its account name is derived from the subscription ID hash and avoids service keywords that trigger an [Azure SDK endpoint parsing issue](../polaris/azure-directory-sas-account-name-bug.en.md). It does not change the existing Parquet write path.

The corresponding Snowflake external stage URL is:

```text
azure://<account-name>.blob.core.windows.net/streamify/
```

This configuration does not clean up data automatically; checkpoints must remain available for stream recovery.

<a id="runtime-identities"></a>

### Application identities and permissions

| Purpose | Identity and permissions | Where it is configured |
| --- | --- | --- |
| Deploy resources from your Mac | Your Azure user and deployment permissions | Azure CLI login and subscription IAM |
| Inspect data in both accounts in the portal | Your Azure user, Storage Blob Data Reader at account scope | Created by Terraform |
| Spark reads and writes the existing `streamify` container | VM managed identity, Storage Blob Data Contributor | Created by Terraform |
| Airflow reads the existing `streamify` container | VM managed identity, Storage Blob Data Reader | Created by Terraform |
| Polaris accesses the Iceberg account | Separate Azure service principal, Storage Blob Data Contributor | Created by Terraform from the principal Object ID |
| AWS Snowflake reads ADLS | An Azure service principal associated with Snowflake | Authorized using [Snowflake setup](../snowflake/README.en.md) |

A managed identity is an application identity that Azure manages for the VM. There are no credentials to save manually. After Terraform creates the identity and permissions, Spark and other applications still need to be configured to use that identity.

## 5. State and later changes

Azure state is stored locally in `azure.tfstate`. Keep the state file so Terraform can track the resources it created.

To change VM sizes later, edit `terraform.tfvars` or the defaults and run `terraform plan`. Review any downtime or resource replacement before running `apply`.

## 6. Stop or delete resources

Between sessions, stop all five VMs in the portal and confirm their status is **Stopped (deallocated)**.
You can also deallocate them individually with Azure CLI, for example:

```bash
az vm deallocate --resource-group "<resource-group>" --name "<vm-name>"
```

Deallocation stops compute charges. Disks, public IPs, and ADLS still incur charges. This configuration has no automatic shutdown.

The script starts or stops only the **five project VMs** in `streamify-rg` in the current Azure CLI subscription: Kafka, Airflow, Spark Master, and two Workers. It does not touch other VMs. Run from the project root on your Mac:

```bash
# Preview the subscription and targets without stopping anything
bash scripts/bulk_operate_vm.sh stop --dry-run

# After reviewing the scope, stop and deallocate the VMs
bash scripts/bulk_operate_vm.sh stop

# Start the five VMs
bash scripts/bulk_operate_vm.sh start
```

`start` and `stop` both support `--dry-run`; an explicit action is required. Startup verifies VM power state, not the readiness of services inside Docker.

The script waits for each operation and checks the resulting power state. If one VM fails, it continues with the others and returns a failure status at the end.
The target resource group and five VM names match `terraform/main.tf`. Select the subscription with `az account set`; no account details or IPs are stored in the script.


Only when you no longer need the resources, run this from `terraform/`:

```bash
terraform destroy
```

It deletes the resources managed by this state and their associated data. It is not a routine shutdown command.

Reference: [Install Terraform](https://developer.hashicorp.com/terraform/install)

- [Terraform authentication with Azure CLI](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/azure_cli)
- [Managed identities](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
