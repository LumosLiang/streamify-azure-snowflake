# Set Up Polaris and PostgreSQL on the Spark Master

[中文](polaris.md) | English

Polaris and its PostgreSQL metadata database run in Docker containers on the Spark Master VM. This step configures Polaris access to ADLS Gen2; it does not create an Iceberg catalog or table yet.

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

`.env` is ignored by Git and must not be committed. Keep `POLARIS_CLIENT_ID` and `POLARIS_CLIENT_SECRET`; they are the credentials of the initial root principal.

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

Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_CLIENT_SECRET` in `polaris/.env` on the Spark Master VM from the command's `tenant`, `appId`, and `password` output. Do not commit the output or `.env`. Polaris uses these credentials to access storage and later vend short-lived credentials to table clients.

## 4. Start and check the service

```bash
docker compose up -d
docker compose ps
docker compose logs bootstrap
curl http://localhost:8182/q/health
```

`bootstrap` creates the `POLARIS` realm once and then exits normally. PostgreSQL and Polaris remain running. The API uses port `8181`; management and health checks use `8182`.
The health check only confirms that the service is running. ADLS access must be verified after creating a catalog and table.

To inspect or stop the services later:

```bash
docker compose logs --follow polaris
docker compose down
```

Do not run `docker compose down -v`; it deletes the Polaris metadata stored in the PostgreSQL volume.

Reference: [Polaris Azure storage configuration](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/).
