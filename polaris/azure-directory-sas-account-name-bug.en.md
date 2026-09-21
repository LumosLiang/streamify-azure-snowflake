# Azure directory SAS `accountName` issue in Polaris 1.7.0

[中文](azure-directory-sas-account-name-bug.md) | English

## How we ran into this problem

We encountered this issue while using Spark SQL to create our first Iceberg table through Polaris.

The environment used Apache Polaris 1.7.0, `azure-storage-file-datalake` 12.28.0, and `azure-storage-blob` 12.35.0. Following the official documentation, we configured the catalog with:

```text
abfss://<container>@<account>.dfs.core.windows.net/<path>/
```

The Storage Account had HNS enabled, and Polaris was configured with `hierarchical: true`. Spark could connect to Polaris, and the namespace had already been created. The failure appeared when we ran `CREATE TABLE`:

```text
NullPointerException: The argument must not be null or an empty string.
Argument name: accountName.
```

At first, this looked like an Azure Storage or Polaris configuration problem. We checked HNS, the catalog location, RBAC, and the service principal. The logs showed that Polaris had successfully obtained a token through the Azure service principal. The actual failure occurred when Polaris tried to create a directory-scoped SAS for Spark:

```text
DataLakePathClient.generateUserDelegationSas
```

Authentication had already completed. The problem was in the Azure SDK path that generated a SAS from the storage URL.

## The Storage Account name was triggering an SDK bug

Looking further into `BlobUrlParts.parseNonIpUrl` in `azure-storage-blob` 12.35.0 showed that it identifies the endpoint type by checking whether the host contains `blob` or `dfs`:

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

This happened to collide with the name we had originally chosen for the Storage Account: the account name itself contained `blob`. For a DFS endpoint such as:

```text
<account-containing-blob>.dfs.core.windows.net
```

both `isBlobEndpoint` and `isDfsEndpoint` become `true`, and the code enters the Blob branch first. The SDK then searches a DFS host for a Blob endpoint, fails to extract `accountName`, and throws the null-value exception while generating the directory-scoped SAS.

To make sure this was not only a theory, we tested with the exact Azure SDK JARs from the Polaris 1.7.0 container:

- A normal Storage Account name produced the correct `accountName`.
- A name containing `blob` consistently produced `accountName=null`.
- Calling another Azure SDK overload and supplying the account name explicitly generated the SAS successfully.

The endpoint-detection logic came from Azure SDK PR #48468, merged in March 2026 and later shipped in `azure-storage-blob` 12.35.0. As of 2026-09-21, no public issue or fix PR was found for this exact case, and the Azure SDK `main` branch still contains the same checks.

## How we resolved it in this project

We could have maintained a patched Polaris image, but that would add a source fork that this learning project would need to keep up to date. Azure Storage Accounts cannot be renamed, but no Iceberg table had been created successfully in the new container, so moving the empty path was inexpensive.

We chose the simpler route:

1. Create a new HNS-enabled Storage Account through Terraform, with a name that contains neither `blob` nor `dfs`.
2. Recreate the `streamify-iceberg` container in the new account.
3. Reapply the RBAC assignments for the Polaris service principal.
4. Remove the empty catalog, then recreate the catalog and Spark grants against the new account.

This did not disable HNS or change the directory-scoped SAS and ADLS Gen2 design. The existing Parquet data stayed in its original Storage Account; only the unused Iceberg path moved.

After the move, we reran Spark SQL `CREATE TABLE`, `INSERT`, and `SELECT`. All three succeeded, confirming the complete path across Spark, Polaris, directory-scoped SAS, ADLS Gen2, and the Iceberg table.

## Source fix when the Storage Account cannot be replaced

If the same problem occurs in an environment where replacing the Storage Account is not practical, `AzureCredentialsStorageIntegration.java` in Polaris 1.7.0 can be changed instead. Polaris has already parsed the correct Storage Account name from the ADLS URI, so it can pass that value explicitly to the Azure SDK:

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

The patch does not widen the credential scope or storage permissions. It only bypasses the faulty host inference with an account name Polaris already knows. We compiled it against the actual dependencies in the Polaris 1.7.0 image and verified it with an offline SAS-generation test. This project does not use the patched image, but the fix remains available when moving the Storage Account is not an option.

References: [Polaris 1.7.0 Azure storage configuration](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/), [Azure SDK PR #48468 that introduced the endpoint parsing change](https://github.com/Azure/azure-sdk-for-java/pull/48468), [current Azure SDK BlobUrlParts](https://github.com/Azure/azure-sdk-for-java/blob/main/sdk/storage/azure-storage-blob/src/main/java/com/azure/storage/blob/BlobUrlParts.java), and [Polaris 1.7.0 Azure credential vending source](https://github.com/apache/polaris/blob/apache-polaris-1.7.0/polaris-core/src/main/java/org/apache/polaris/core/storage/azure/AzureCredentialsStorageIntegration.java).
