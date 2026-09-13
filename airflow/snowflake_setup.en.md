# Initialize Snowflake

[中文](snowflake_setup.md) | English

This step creates only the user, role, warehouse, database, and schemas required for the dbt connection. dbt uses a dedicated `SERVICE` user with an RSA key pair instead of a password.

## 1. Generate the key pair on the Airflow VM

```bash
cd ~/streamify
mkdir -p airflow/secrets
chmod 700 airflow/secrets

openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 aes-256-cbc \
  -inform PEM -out airflow/secrets/snowflake_rsa_key.p8

openssl rsa -in airflow/secrets/snowflake_rsa_key.p8 -pubout \
  -out airflow/secrets/snowflake_rsa_key.pub

chmod 600 airflow/secrets/snowflake_rsa_key.p8
```

The first command prompts for a private-key passphrase. Neither the private key nor its passphrase belongs in Git.

Print the public key as the single line required by Snowflake SQL:

```bash
grep -v '^-----' airflow/secrets/snowflake_rsa_key.pub | tr -d '\n'
```

## 2. Initialize Snowflake

Open a Snowsight worksheet with an administrator role that can create account objects. Open `airflow/snowflake_setup.sql`, replace `<snowflake-public-key-body>` with the output above, and run the file.

It creates:

- user: `STREAMIFY_DBT`
- role: `STREAMIFY_TRANSFORMER`
- warehouse: `STREAMIFY_TRANSFORM_WH`, X-Small, auto-suspended after 60 idle seconds
- database: `STREAMIFY`
- schemas: `STREAMIFY_STG` and `STREAMIFY_PROD`

Run the final `ADD KEY PAIR` statement only once. Skip it when rerunning the rest of the file.

## 3. Configure the Airflow VM

```bash
cp airflow/.env.example airflow/.env
```

Set `SNOWFLAKE_ACCOUNT` and put the passphrase chosen above in `SNOWFLAKE_PRIVATE_KEY_PASSPHRASE`. The remaining Snowflake values already match the SQL setup.

Build the image using the [Airflow setup](../setup/airflow.en.md), then run `dbt debug` using the [dbt setup](../setup/dbt.en.md).
