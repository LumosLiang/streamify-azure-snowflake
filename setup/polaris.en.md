# Set Up Polaris and PostgreSQL on the Spark Master

[中文](polaris.md) | English

Polaris and its PostgreSQL metadata database run in Docker containers on the Spark Master VM. This guide configures Polaris access to ADLS Gen2, an Azure catalog, and a Spark client identity; creating an Iceberg table is the next step.

## 1. Prepare the VM

```bash
ssh streamify-spark
cd ~/streamify-azure-snowflake
bash scripts/vm_setup.sh
```

If Docker was just installed, log out and reconnect before continuing.

## 2. Create the local configuration

```bash
cd ~/streamify-azure-snowflake/polaris
cp .env.example .env
```

Edit `.env` and set a different random value for each `POLARIS_` variable:

```bash
openssl rand -hex 24
```

`POLARIS_CLIENT_ID` and `POLARIS_CLIENT_SECRET` are the credentials of the initial root principal.

## 3. Configure an ADLS access identity

Polaris uses a separate Azure service principal to access storage. It is distinct from the Polaris root principal. On your Mac, confirm that Azure CLI is using the deployment subscription, then get the Storage Account resource ID:

```bash
az storage account show --resource-group streamify-rg \
  --name "<storage-account-name>" --query id --output tsv
```

Create the service principal once and grant it `Storage Blob Data Contributor` on that Storage Account:

```bash
az ad sp create-for-rbac --name streamify-polaris-storage \
  --role "Storage Blob Data Contributor" \
  --scopes "<storage-account-resource-id>"
```

`.env.example` includes the following values. If the `.env` on the Spark Master already exists, add them to the end of the file:

```bash
AZURE_TENANT_ID=<tenant>
AZURE_CLIENT_ID=<appId>
AZURE_CLIENT_SECRET=<password>
```

They map to the command output's `tenant`, `appId`, and `password`. Docker Compose passes them to Polaris. When an Azure catalog is created later, Polaris uses the service-principal credentials through the Azure SDK `DefaultAzureCredential` chain to access ADLS and vend short-lived SAS tokens to table clients.

## 4. Start and check the service

```bash
docker compose up -d
docker compose ps
docker compose logs bootstrap
curl http://localhost:8182/q/health
```

`bootstrap` creates the `POLARIS` realm once and then exits normally. PostgreSQL and Polaris remain running. The API uses port `8181`; management and health checks use `8182`.
The health check only confirms that the service is running. ADLS access must be verified after creating a catalog and table.

## 5. Create the Azure catalog

Run this in the `polaris/` directory on the Spark Master:

```bash
bash create_catalog.sh \
  <storage-account-name> \
  <container-name> \
  <catalog-name> \
  <base-path>
```

For example, the dedicated Iceberg container currently prepared for this project can use:

```bash
bash create_catalog.sh \
  <storage-account-name> \
  streamify-iceberg \
  streamify_iceberg \
  lake
```

The script uses the Polaris root principal and Azure service principal in `.env`. Its four arguments are the Azure Storage Account, Azure container, Polaris catalog name, and the table root path inside the container. The container and catalog names are independent; `lake` can instead be `warehouse` or `lake/raw`.

The example's default table location is:

```text
abfss://streamify-iceberg@<storage-account-name>.dfs.core.windows.net/lake/
```

It does not create a namespace or Iceberg table. If the catalog already exists, the script exits without overwriting its configuration.

## 6. Create the Spark principal

Spark does not use the Polaris root principal. It needs its own principal, principal role, and catalog role. The script connects them and grants `CATALOG_MANAGE_CONTENT` on this catalog, which permits creating, reading, and writing tables.

Install the Polaris CLI on the Spark Master first:

```bash
sudo apt-get update
sudo apt-get install -y pipx
pipx install apache-polaris
"$HOME/.local/bin/polaris" --version
```

Then run this in the `polaris/` directory:

```bash
bash create_spark_principal.sh \
  <catalog-name> \
  <principal-name> \
  <principal-role-name> \
  <catalog-role-name>
```

The four names identify the catalog, Spark identity, identity role, and catalog role. The script first checks that the catalog exists and refuses to overwrite a principal or role with the same name. On success, it prints the `clientId` and `clientSecret` needed in the next Spark step; it does not change Spark configuration or create a table.

## 7. Inspect or stop the services

```bash
docker compose logs --follow polaris
docker compose down
```

Do not run `docker compose down -v`; it deletes the Polaris metadata stored in the PostgreSQL volume.

Reference: [Polaris Azure storage configuration](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/).
