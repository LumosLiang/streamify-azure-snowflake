# Azure 账号与权限

中文 | [English](azure.en.md)

先准备一个可用的 Azure 订阅。Terraform 默认把计算和存储资源部署到新加坡区域；Snowflake 位于 AWS。

## 1. 确认订阅

1. 打开 [Azure Portal](https://portal.azure.com)，进入 **Subscriptions**，选择用于部署的订阅。
2. 确认状态为 **Enabled**，记录 **Subscription ID**。

## 2. 确认部署权限

在订阅的 **Access control (IAM) → View my access** 中查看自己的角色。

Terraform 需要创建资源，也需要给 VM 分配存储访问权限。**Owner** 可以执行这些操作；只有 **Contributor** 时，还需要管理员授予相应的角色分配权限。

在 **Quotas** 中确认部署区域至少有 12 vCPU 额度，其中 Dasv5 系列需要 10 vCPU，Easv5 系列需要 2 vCPU。

如果 Terraform 报 Resource Provider 未注册，在订阅的 **Resource providers** 页面检查对应服务。

## 3. 在 Mac 安装 Azure CLI

安装 Azure CLI：

```bash
brew install azure-cli
```

接下来按 Terraform 文档中的 [Azure 登录](terraform.md#azure-login) 选择订阅。VM 和 Snowflake 的权限说明统一放在 [运行身份与权限](terraform.md#runtime-identities)。

## 参考

- [Azure CLI 安装](https://learn.microsoft.com/cli/azure/install-azure-cli-macos)
