# Azure account and access

[中文](azure.md) | English

Start with an active Azure subscription. Terraform deploys compute and storage to Singapore by default; Snowflake runs on AWS.

## 1. Check the subscription

1. Open [Azure Portal](https://portal.azure.com), go to **Subscriptions**, and select the subscription for this deployment.
2. Check that its status is **Enabled** and copy the **Subscription ID**.

## 2. Check deployment permissions

Open **Access control (IAM) → View my access** on the subscription.

Terraform needs to create resources and assign storage permissions to VMs. **Owner** can do both. **Contributor** alone cannot assign roles; an administrator must grant the additional role-assignment permissions.

Under **Quotas**, check that the deployment region has at least 12 available vCPUs: 10 in the Dasv5 family and 2 in the Easv5 family.

If Terraform reports an unregistered Resource Provider, check it under the subscription's **Resource providers** page.

## 3. Install Azure CLI on your Mac

Install Azure CLI:

```bash
brew install azure-cli
```

Continue with [Azure login](terraform.en.md#azure-login) in the Terraform guide. The [application identities](terraform.en.md#runtime-identities) section explains the VM and Snowflake permissions.

## References

- [Install Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli-macos)
