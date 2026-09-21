# Polaris 1.7.0 的 Azure 目录级 SAS `accountName` 为空的问题

中文 | [English](azure-directory-sas-account-name-bug.en.md)

## 事情是怎么发生的

这个问题发生在我们第一次尝试通过 Spark SQL，在 Polaris catalog 中创建 Iceberg 表的时候。

当时使用的是 Apache Polaris 1.7.0、`azure-storage-file-datalake` 12.28.0 和 `azure-storage-blob` 12.35.0。Catalog 按照官方文档配置为：

```text
abfss://<container>@<account>.dfs.core.windows.net/<path>/
```

Storage Account 开启了 HNS，Polaris 中也设置了 `hierarchical: true`。Spark 能连接 Polaris，namespace 也已经创建成功，但执行 `CREATE TABLE` 时突然失败：

```text
NullPointerException: The argument must not be null or an empty string.
Argument name: accountName.
```

这个错误看起来很像 Azure Storage 或 Polaris 的配置有问题。我们一开始也怀疑过 HNS、catalog location、RBAC 和 service principal，但日志显示 Polaris 已经通过 Azure service principal 成功拿到了 token。真正失败的位置，是 Polaris 准备为 Spark 生成目录级 SAS 的时候：

```text
DataLakePathClient.generateUserDelegationSas
```

这意味着身份认证已经完成，问题发生在 Azure SDK 根据存储地址生成 SAS 的阶段。

## 最后发现是 Storage Account 的名字触发了 bug

继续看 `azure-storage-blob` 12.35.0 的 `BlobUrlParts.parseNonIpUrl`，可以看到它通过字符串中是否包含 `blob` 或 `dfs` 来判断 endpoint 类型：

```java
boolean isBlobEndpoint =
    host != null && host.contains(Constants.UrlConstants.BLOB_URI_SUBDOMAIN);
boolean isDfsEndpoint =
    host != null && host.contains(Constants.UrlConstants.DFS_URI_SUBDOMAIN);

if (isBlobEndpoint) {
  parts.setAccountName(
      StorageImplUtils.getAccountNameFromHost(
          host, Constants.UrlConstants.BLOB_URI_SUBDOMAIN));
} else if (isDfsEndpoint) {
  parts.setAccountName(
      StorageImplUtils.getAccountNameFromHost(
          host, Constants.UrlConstants.DFS_URI_SUBDOMAIN));
}
```

问题恰好出在这里：我最初给 Storage Account 取名时，名字本身包含了 `blob`。因此对于下面这种本来属于 DFS 的地址：

```text
<account-containing-blob>.dfs.core.windows.net
```

`isBlobEndpoint` 和 `isDfsEndpoint` 都会变成 `true`，而代码先进入 Blob 分支。SDK 随后尝试从一个 DFS host 中寻找 Blob endpoint，最终没有解析出 `accountName`，于是生成目录级 SAS 时抛出了我们看到的空值异常。

为了确认这不是猜测，我们直接使用 Polaris 1.7.0 容器里的同一套 Azure SDK JAR 做了离线测试：

- 普通 Storage Account 名可以正常解析出 `accountName`。
- 名字中包含 `blob` 时，可以稳定复现 `accountName=null`。
- 使用 Azure SDK 提供的另一个 overload，显式传入账号名后，SAS 可以正常生成。

这段 endpoint 识别逻辑来自 Azure SDK PR #48468。它在 2026 年 3 月合并，随后进入 `azure-storage-blob` 12.35.0。截至 2026-09-21，没有找到覆盖这个精确场景的公开 issue 或修复 PR，Azure SDK 的 `main` 分支仍保留相同判断。

## 我们最终怎么处理

理论上可以维护一个打过补丁的 Polaris 镜像，但这会让实验项目多出一条需要长期维护的源码分支。另一方面，Azure Storage Account 无法直接改名，但当时新的 Iceberg container 中还没有成功创建任何表，因此迁移成本很低。

我们最后选择了更简单的处理方式：

1. 通过 Terraform 创建一个新的 HNS Storage Account，名字不包含 `blob` 或 `dfs`。
2. 在新账号中重新创建 `streamify-iceberg` container。
3. 重新配置 Polaris service principal 的 RBAC。
4. 删除原来的空 catalog，并在新账号上重新创建 catalog 和 Spark 授权。

这个方案没有关闭 HNS，也没有改变目录级 SAS 和 ADLS Gen2 的设计。现有 Parquet 数据继续留在原来的 Storage Account 中，只有尚未投入使用的 Iceberg 路径发生了变化。

迁移完成后，我们重新执行了 Spark SQL 的 `CREATE TABLE`、`INSERT` 和 `SELECT`，三步全部成功。至此可以确认 Spark、Polaris、目录级 SAS、ADLS Gen2 和 Iceberg 表的完整链路已经打通。

## 如果不能更换 Storage Account

如果以后在已有数据的环境中遇到同样的问题，无法通过新建 Storage Account 解决，也可以修改 Polaris 1.7.0 的 `AzureCredentialsStorageIntegration.java`。Polaris 其实已经从 ADLS URI 中解析出了正确的 Storage Account 名，只需要在调用 Azure SDK 时显式传进去：

```diff
 import com.azure.core.credential.AccessToken;
 import com.azure.core.credential.TokenRequestContext;
+import com.azure.core.util.Context;

       sasToken =
           getAdlsUserDelegationSas(
               startTime,
               sanitizedEndTime,
               sanitizedEndTime,
+              location.getStorageAccount(),
               storageDnsName,
               location.getContainer(),
               pathSasPermission,
               path,
               Mono.just(accessToken));

 private static String getAdlsUserDelegationSas(
     OffsetDateTime startTime,
     OffsetDateTime endTime,
     OffsetDateTime sasExpiry,
+    String storageAccountName,
     String storageDnsName,
     String fileSystemNameOrContainer,
     PathSasPermission pathSasPermission,
     String path,
     Mono<AccessToken> accessTokenMono) {

   return new DataLakePathClientBuilder()
       .endpoint(endpoint)
       .fileSystemName(fileSystemNameOrContainer)
       .pathName(path)
       .buildDirectoryClient()
-      .generateUserDelegationSas(signatureValues, userDelegationKey);
+      .generateUserDelegationSas(
+          signatureValues, userDelegationKey, storageAccountName, Context.NONE);
```

这个补丁不会改变凭据范围，也不会扩大存储权限；它只是绕过有问题的 host 推断，使用 Polaris 已经知道的账号名。我们已经用 Polaris 1.7.0 镜像中的实际依赖完成编译，并通过离线 SAS 生成测试验证过这段修改。当前项目没有采用补丁镜像，但后续遇到相同问题时，它仍然是一条可行的修复路径。

参考：[Polaris 1.7.0 Azure storage configuration](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/)、[引入 endpoint 解析改动的 Azure SDK PR #48468](https://github.com/Azure/azure-sdk-for-java/pull/48468)、[Azure SDK 当前 BlobUrlParts](https://github.com/Azure/azure-sdk-for-java/blob/main/sdk/storage/azure-storage-blob/src/main/java/com/azure/storage/blob/BlobUrlParts.java)、[Polaris 1.7.0 Azure credential vending source](https://github.com/apache/polaris/blob/apache-polaris-1.7.0/polaris-core/src/main/java/org/apache/polaris/core/storage/azure/AzureCredentialsStorageIntegration.java)。
