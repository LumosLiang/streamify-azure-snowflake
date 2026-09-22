# Set Up Polaris and PostgreSQL on the Spark Master

[中文](polaris.md) | English

Polaris and its PostgreSQL metadata database run in Docker containers on the Spark Master VM. This guide configures Polaris access to ADLS Gen2, an Azure catalog, a Spark client identity, and one isolated Iceberg validation table. It does not change the current Parquet streaming path.

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

Polaris uses a separate Azure service principal to access storage. It is distinct from the Polaris root principal. Create this identity once:

```bash
az ad sp create-for-rbac \
  --name streamify-polaris-storage
```

Use the returned `appId` to get the service principal Object ID:

```bash
az ad sp show --id "<appId>" --query id --output tsv
```

Set `polaris_service_principal_object_id` in `terraform.tfvars` to that value. Terraform grants `Storage Blob Data Contributor` on the dedicated Iceberg Storage Account.

`.env.example` includes the following values. If the `.env` on the Spark Master already exists, add them to the end of the file:

```bash
AZURE_TENANT_ID=<tenant>
AZURE_CLIENT_ID=<appId>
AZURE_CLIENT_SECRET=<password>
```

They map to the creation command's `tenant`, `appId`, and `password`. Docker Compose passes them to Polaris. When an Azure catalog is created later, Polaris uses the service-principal credentials through the Azure SDK `DefaultAzureCredential` chain to access ADLS and vend short-lived SAS tokens to table clients.

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

The script also enables namespace custom locations for the catalog. Spark places the `validation` namespace at `lake/validation/` under the default base location; without this property, Polaris rejects that path.

It does not create a namespace or Iceberg table. If the catalog already exists, the script exits without overwriting its configuration.

### View catalogs

The current deployment has no Polaris UI. To inspect catalogs, use the Polaris CLI from the `polaris/` directory on the Spark Master. Load the root principal in `.env`, then list all catalogs:

```bash
set -a
source .env
set +a

"$HOME/.local/bin/polaris" \
  --host 127.0.0.1 \
  --port 8181 \
  --client-id "$POLARIS_CLIENT_ID" \
  --client-secret "$POLARIS_CLIENT_SECRET" \
  catalogs list
```

To inspect one catalog's Azure location and `hierarchical` setting:

```bash
"$HOME/.local/bin/polaris" \
  --host 127.0.0.1 \
  --port 8181 \
  --client-id "$POLARIS_CLIENT_ID" \
  --client-secret "$POLARIS_CLIENT_SECRET" \
  catalogs get <catalog-name>
```

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

Using the catalog example from the previous step, the four arguments can be:

```bash
bash create_spark_principal.sh \
  streamify_iceberg \
  spark_client \
  spark_principal_role \
  spark_catalog_role
```

The first argument must be an existing Polaris catalog. The remaining three are authorization objects we name for Spark: `spark_client` is the principal Spark uses to sign in to Polaris, `spark_principal_role` represents that principal's permission set, and `spark_catalog_role` is a role inside the catalog. The script connects them as follows, then grants table creation, read, and write access to the catalog role:

```text
spark_client → spark_principal_role → spark_catalog_role → CATALOG_MANAGE_CONTENT
```

The script first checks that the catalog exists and refuses to overwrite a principal or role with the same name. On success, it prints the `clientId` and `clientSecret` needed in the next step. Persist them on the Spark Master in `~/.polaris_spark.env`:

```bash
cat > "$HOME/.polaris_spark.env" <<'EOF'
export POLARIS_SPARK_CLIENT_ID=<clientId>
export POLARIS_SPARK_CLIENT_SECRET=<clientSecret>
EOF
```

This file holds the Polaris principal shared by Spark clients; `spark-iceberg.env` loads it. `polaris/.env` continues to configure the Polaris service and its Azure storage identity.

## 7. Validate the first Iceberg table with Spark SQL

In the `polaris/` directory on the Spark Master, load the Spark environment and Spark principal credentials:

```bash
source "$HOME/.config/streamify/spark-iceberg.env"
```

This `SPARK_MASTER_URL` command gets the Spark Master's private IP and forms its standalone Master URL. Then start an interactive Spark SQL session yourself. Replace `<catalog-name>` with the existing Azure catalog in Polaris:

```bash
"$SPARK_HOME/bin/spark-sql" \
  --master "$SPARK_MASTER_URL" \
  --packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0,org.apache.iceberg:iceberg-azure-bundle:1.11.0 \
  --conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
  --conf spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog \
  --conf spark.sql.catalog.polaris.type=rest \
  --conf spark.sql.catalog.polaris.uri=http://127.0.0.1:8181/api/catalog \
  --conf spark.sql.catalog.polaris.oauth2-server-uri=http://127.0.0.1:8181/api/catalog/v1/oauth/tokens \
  --conf spark.sql.catalog.polaris.token-refresh-enabled=false \
  --conf spark.sql.catalog.polaris.warehouse=<catalog-name> \
  --conf spark.sql.catalog.polaris.scope=PRINCIPAL_ROLE:ALL \
  --conf spark.sql.catalog.polaris.credential="${POLARIS_SPARK_CLIENT_ID}:${POLARIS_SPARK_CLIENT_SECRET}" \
  --conf spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation=vended-credentials \
  --conf spark.sql.catalog.polaris.io-impl=org.apache.iceberg.azure.adlsv2.ADLSFileIO
```

`polaris` is the local catalog alias for this Spark session; `<catalog-name>` is the existing Azure catalog in Polaris. `--packages` adds the Iceberg 1.11 runtime for Spark 4.1 and the Azure bundle. The remaining `spark.sql.catalog.polaris.*` parameters define the REST catalog, OAuth authentication, catalog selection, and ADLS FileIO. When creating and loading tables, Polaris vends short-lived ADLS SAS tokens to Spark, so Spark needs no static Azure storage credentials.

At the `spark-sql` prompt, open `validate_iceberg.sql` and run its statements one at a time. They create `polaris.validation`, create the `spark_connectivity` table, write one validation row only when it is absent, and query the result.

On success, the query includes:

```text
1  polaris-iceberg
```

This step creates test data only in the dedicated Iceberg container. It does not read from or replace the existing Kafka, Spark Streaming, or Parquet output.

## 8. Inspect or stop the services

```bash
docker compose logs --follow polaris
docker compose down
```

Do not run `docker compose down -v`; it deletes the Polaris metadata stored in the PostgreSQL volume.

References: [Polaris Azure storage configuration](https://polaris.apache.org/releases/1.7.0/configuration/configuring-polaris-for-production/configuring-azure-blob-cloud-storage-specific/), [using Polaris with Spark](https://polaris.apache.org/releases/1.7.0/getting-started/using-polaris/), and [Iceberg 1.11.0 releases](https://iceberg.apache.org/releases/).
