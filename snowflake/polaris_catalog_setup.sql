-- Connect Snowflake to the self-hosted Apache Polaris catalog.
-- Before running this file:
-- 1. Replace the placeholders with a public HTTPS Polaris endpoint and the
--    credentials of a dedicated read-only Polaris principal.
-- 2. Grant that principal read-only access to the whole Polaris catalog,
--    including TABLE_READ_DATA for vended read-only SAS credentials.
-- 3. The endpoint must be reachable by Snowflake. localhost and the current
--    private-only Polaris endpoint are not reachable from Snowflake.

-- CREATE OR REPLACE updates an earlier integration definition.
-- Snowflake won't replace an integration while dependent Iceberg tables use it.
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE CATALOG INTEGRATION STREAMIFY_POLARIS_INT
  CATALOG_SOURCE = POLARIS
  TABLE_FORMAT = ICEBERG
  REST_CONFIG = (
    CATALOG_URI = 'https://<polaris-hostname>/api/catalog'
    CATALOG_API_TYPE = PUBLIC
    CATALOG_NAME = '<polaris-catalog-name>'
    ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS
  )
  REST_AUTHENTICATION = (
    TYPE = OAUTH
    OAUTH_CLIENT_ID = '<polaris-readonly-client-id>'
    OAUTH_CLIENT_SECRET = '<polaris-readonly-client-secret>'
    OAUTH_ALLOWED_SCOPES = ('PRINCIPAL_ROLE:<polaris-readonly-principal-role>')
  )
  ENABLED = TRUE;

-- Confirms that Snowflake can authenticate to Polaris and read catalog metadata.
SELECT SYSTEM$VERIFY_CATALOG_INTEGRATION('STREAMIFY_POLARIS_INT');

-- With no ALLOWED_NAMESPACES filter, discover every namespace in the catalog.
CREATE DATABASE STREAMIFY_ICEBERG
  LINKED_CATALOG = (
    CATALOG = 'STREAMIFY_POLARIS_INT',
    ALLOWED_WRITE_OPERATIONS = NONE
  )
  CATALOG_CASE_SENSITIVITY = CASE_SENSITIVE;

-- Check the catalog-linked database synchronization status.
SELECT SYSTEM$CATALOG_LINK_STATUS('STREAMIFY_ICEBERG');

-- Snowflake should expose the Polaris namespace as a schema and the table under it.
SELECT *
FROM STREAMIFY_ICEBERG."streamify_raw"."listen_events"
LIMIT 10;
