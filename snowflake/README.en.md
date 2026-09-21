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
