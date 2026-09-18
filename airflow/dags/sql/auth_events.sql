-- LEARNING EXERCISE / 学习练习
-- Load the auth_events Parquet files from STREAMIFY_ADLS_STAGE into
-- STREAMIFY.STREAMIFY_STG.AUTH_EVENTS.
-- Refer to listen_events.sql and page_view_events.sql, then write the COPY INTO
-- statement here. auth_events will not be loaded until this file is completed.

COPY INTO STREAMIFY.STREAMIFY_STG.AUTH_EVENTS
FROM @STREAMIFY.STREAMIFY_STG.STREAMIFY_ADLS_STAGE/auth_events/
FILE_FORMAT = (FORMAT_NAME = STREAMIFY.STREAMIFY_STG.STREAMIFY_PARQUET_FORMAT)
MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
PATTERN = '.*[.]parquet'
ON_ERROR = 'ABORT_STATEMENT';
