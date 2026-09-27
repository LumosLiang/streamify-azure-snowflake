-- Connect Snowflake to the self-hosted Apache Polaris REST catalog.
-- Before running this file:
-- 1. Replace the placeholders with a public HTTPS Polaris endpoint and the
--    credentials of a dedicated read-only Polaris principal.
-- 2. Grant that principal access only to the streamify_raw namespace and its
--    tables, including TABLE_READ_DATA for vended read-only SAS credentials.
-- 3. The endpoint must be reachable by Snowflake. localhost and the current
--    private-only Polaris endpoint are not reachable from Snowflake.

USE ROLE ACCOUNTADMIN;

CREATE CATALOG INTEGRATION IF NOT EXISTS STREAMIFY_POLARIS_INT
  CATALOG_SOURCE = ICEBERG_REST
  TABLE_FORMAT = ICEBERG
  REST_CONFIG = (
    CATALOG_URI = 'https://<polaris-hostname>/api/catalog'
    CATALOG_API_TYPE = PUBLIC
    CATALOG_NAME = '<polaris-catalog-name>'
    ACCESS_DELEGATION_MODE = VENDED_CREDENTIALS
  )
  REST_AUTHENTICATION = (
    TYPE = OAUTH
    OAUTH_TOKEN_URI = 'https://<polaris-hostname>/api/catalog/v1/oauth/tokens'
    OAUTH_CLIENT_ID = '<polaris-readonly-client-id>'
    OAUTH_CLIENT_SECRET = '<polaris-readonly-client-secret>'
    OAUTH_ALLOWED_SCOPES = ('PRINCIPAL_ROLE:<polaris-readonly-principal-role>')
  )
  ENABLED = TRUE;

-- Confirms that Snowflake can authenticate to Polaris and read catalog metadata.
SELECT SYSTEM$VERIFY_CATALOG_INTEGRATION('STREAMIFY_POLARIS_INT');

-- Limit automatic discovery to the namespace that contains the streaming table.
CREATE DATABASE STREAMIFY_ICEBERG
  LINKED_CATALOG = (
    CATALOG = 'STREAMIFY_POLARIS_INT'
    ALLOWED_NAMESPACES = ('streamify_raw')
  )
  CATALOG_CASE_SENSITIVITY = CASE_SENSITIVE;

-- Check the catalog-linked database synchronization status.
SELECT SYSTEM$CATALOG_LINK_STATUS('STREAMIFY_ICEBERG');

-- Snowflake should expose the Polaris namespace as a schema and the table under it.
SELECT *
FROM STREAMIFY_ICEBERG."streamify_raw"."listen_events"
LIMIT 10;
