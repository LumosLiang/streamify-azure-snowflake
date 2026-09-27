# Initialize Snowflake

[中文](README.md) | English

This stage creates the objects required for `ADLS2 → Snowflake staging → dbt`.

## 1. Create the Snowflake identity and base objects

Generate an encrypted private key on the Airflow VM:

```bash
cd ~/streamify-azure-snowflake
mkdir -p airflow/secrets
chmod 700 airflow/secrets
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc \
  -inform PEM -out airflow/secrets/snowflake_rsa_key.p8
openssl rsa -in airflow/secrets/snowflake_rsa_key.p8 -pubout \
  -out airflow/secrets/snowflake_rsa_key.pub
chmod 600 airflow/secrets/snowflake_rsa_key.p8
grep -v '^-----' airflow/secrets/snowflake_rsa_key.pub | tr -d '\n'
```

Open `snowflake/setup.sql` in Snowsight, replace the public-key placeholder, and run it. It creates a service user, role, X-Small warehouse, staging/prod schemas, and three staging tables. Run the final `ADD KEY PAIR` statement only once.

## 2. Allow Snowflake to read ADLS2

Get the tenant ID. Read the storage account name from `storage_account_name` in `terraform/terraform.tfvars`:

```bash
az account show --query tenantId -o tsv
```

Replace the placeholders in `snowflake/storage_setup.sql`, then run through `DESC STORAGE INTEGRATION`. From its output:

1. Open `AZURE_CONSENT_URL` and grant consent.
2. In the Azure Storage Account **Access control (IAM)** page, grant **Storage Blob Data Reader** to the enterprise application named by `AZURE_MULTI_TENANT_APP_NAME`.
3. Return to Snowsight and run the rest of the file. The final `LIST` should show the Parquet files.

The URL uses `azure://<account>.blob.core.windows.net/streamify/`; this is also the correct form for ADLS Gen2.

## 3. Configure Airflow

```bash
test -f airflow/.env || cp airflow/.env.example airflow/.env
```

Set `SNOWFLAKE_ACCOUNT` and the private-key passphrase. The other defaults can remain unchanged.

Then build the image using [Airflow setup](../setup/airflow.en.md) and verify the connection using [dbt setup](../setup/dbt.en.md).

## 4. Connect to Iceberg tables managed by Polaris

The existing `STREAMIFY_AZURE_INT` is only for Snowflake to read Parquet staging files. The Iceberg table is managed by a separate Polaris catalog. Snowflake connects to Polaris through an Iceberg REST catalog integration, then receives short-lived read-only SAS credentials from Polaris to access the ADLS files. This path does not reuse the Parquet storage integration.

Complete these two prerequisites before running [polaris_catalog_setup.sql](polaris_catalog_setup.sql):

1. Give the Polaris REST API an HTTPS address that Snowflake can reach. The running service still has only local/private HTTP access. Terraform and Compose now prepare an Azure DNS label, a Caddy HTTPS proxy, and TCP 443 ingress. Follow the [Polaris setup guide](../setup/polaris.en.md), review the plan, apply it yourself, then set the hostname on the Spark Master and start the proxy. `localhost`, a private IP, and an `http://` address will not work in the integration. The Terraform rule makes port 443 reachable from public sources on the Spark Master; Polaris still requires OAuth authentication, and the NSG continues to block public access to ports 8181/8182.
2. Create a dedicated read-only Polaris principal and roles for Snowflake. Grant access only to the `streamify_raw` namespace and its tables, including `TABLE_READ_DATA` so Polaris can vend read-only SAS credentials. Do not reuse Spark's write principal.

After those prerequisites are complete, replace the Polaris HTTPS hostname, catalog name, and read-only principal credentials in the SQL file, then run it in Snowsight as `ACCOUNTADMIN`. `SYSTEM$VERIFY_CATALOG_INTEGRATION` checks Snowflake's authentication and metadata access to Polaris. The catalog-linked database then discovers only `streamify_raw`; the final query checks whether Snowflake can read `listen_events`. The SQL has not been run, so end-to-end behavior remains unverified.

Official references: [Iceberg REST catalog integration](https://docs.snowflake.com/en/user-guide/tables-iceberg-configure-catalog-integration-rest), [vended credentials](https://docs.snowflake.com/en/user-guide/tables-iceberg-configure-catalog-integration-vended-credentials), and [catalog-linked database](https://docs.snowflake.com/en/user-guide/tables-iceberg-catalog-linked-database).
