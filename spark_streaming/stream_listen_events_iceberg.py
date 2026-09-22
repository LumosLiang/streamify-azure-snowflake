"""A parallel Kafka-to-Iceberg streaming job for listen_events.

It must not replace or modify stream_all_events.py, which continues to write
the existing Parquet path. The Iceberg checkpoint container and its Spark VM
managed-identity access must exist before this job is submitted.
"""

import os

from schema import schema
from streaming_utils import create_kafka_read_stream, create_or_get_spark_session, process_stream


LISTEN_EVENTS_TOPIC = "listen_events"
KAFKA_PORT = "9092"
CATALOG_ALIAS = "polaris"


def require_env(variable_name):
    """Return a required environment variable with a clear startup error."""
    value = os.getenv(variable_name)
    if not value:
        raise RuntimeError(f"Set {variable_name} before submitting this job.")
    return value


def build_spark_session(checkpoint_storage_account, catalog_name):
    """Create the Spark session with the Polaris REST catalog configuration."""
    catalog_prefix = f"spark.sql.catalog.{CATALOG_ALIAS}"
    catalog_configs = {
        "spark.sql.extensions": (
            "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
        ),
        catalog_prefix: "org.apache.iceberg.spark.SparkCatalog",
        f"{catalog_prefix}.type": "rest",
        f"{catalog_prefix}.uri": "http://127.0.0.1:8181/api/catalog",
        f"{catalog_prefix}.oauth2-server-uri": (
            "http://127.0.0.1:8181/api/catalog/v1/oauth/tokens"
        ),
        f"{catalog_prefix}.token-refresh-enabled": "false",
        f"{catalog_prefix}.warehouse": catalog_name,
        f"{catalog_prefix}.scope": "PRINCIPAL_ROLE:ALL",
        f"{catalog_prefix}.credential": (
            f"{require_env('POLARIS_SPARK_CLIENT_ID')}:"
            f"{require_env('POLARIS_SPARK_CLIENT_SECRET')}"
        ),
        f"{catalog_prefix}.header.X-Iceberg-Access-Delegation": "vended-credentials",
        f"{catalog_prefix}.io-impl": "org.apache.iceberg.azure.adlsv2.ADLSFileIO",
    }
    return create_or_get_spark_session(
        "Eventsim Listen Events to Iceberg",
        storage_account=checkpoint_storage_account,
        extra_configs=catalog_configs,
    )


def build_listen_events_stream(spark, kafka_address):
    """Create a DataStreamReader for listen_events with the normalized schema."""

    listen_events = create_kafka_read_stream(spark, kafka_address, KAFKA_PORT, LISTEN_EVENTS_TOPIC)
    listen_events = process_stream(listen_events, schema[LISTEN_EVENTS_TOPIC], LISTEN_EVENTS_TOPIC)
    return listen_events


def ensure_listen_events_table(spark, table_identifier):
    """Create the Polaris namespace and Iceberg table for normalized listens."""
    namespace_identifier = ".".join(table_identifier.split(".")[:-1])

    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {namespace_identifier}")
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {table_identifier} (
            artist STRING,
            song STRING,
            duration DOUBLE,
            ts TIMESTAMP,
            sessionid INT,
            auth STRING,
            level STRING,
            itemInSession INT,
            city STRING,
            zip INT,
            state STRING,
            userAgent STRING,
            lon DOUBLE,
            lat DOUBLE,
            userId BIGINT,
            lastName STRING,
            firstName STRING,
            gender STRING,
            registration BIGINT,
            year INT,
            month INT,
            hour INT,
            day INT
        )
        USING iceberg
        PARTITIONED BY (days(ts))
        """
    )



def start_iceberg_writer(stream, table_identifier, checkpoint_path):
    """Start a streaming query that writes to the Iceberg table."""
    
    iceberg_write_stream_query = (
        stream.writeStream
        .format("iceberg")
        .outputMode("append")
        .trigger(processingTime="1 minute")
        .option("checkpointLocation", checkpoint_path)
        .toTable(table_identifier)
    )

    return iceberg_write_stream_query


def main():
    checkpoint_storage_account = require_env("ICEBERG_CHECKPOINT_STORAGE_ACCOUNT")
    checkpoint_container = os.getenv("ICEBERG_CHECKPOINT_CONTAINER", "streamify-checkpoints")
    catalog_name = require_env("POLARIS_CATALOG_NAME")
    kafka_address = require_env("KAFKA_ADDRESS")
    namespace = os.getenv("ICEBERG_NAMESPACE", "streamify_raw")
    table_name = os.getenv("ICEBERG_TABLE", LISTEN_EVENTS_TOPIC)

    table_identifier = f"{CATALOG_ALIAS}.{namespace}.{table_name}"
    checkpoint_path = (
        f"abfss://{checkpoint_container}@{checkpoint_storage_account}.dfs.core.windows.net/"
        f"checkpoint/iceberg/{LISTEN_EVENTS_TOPIC}"
    )
    spark = build_spark_session(checkpoint_storage_account, catalog_name)

    ensure_listen_events_table(spark, table_identifier)
    listen_events = build_listen_events_stream(spark, kafka_address)
    query = start_iceberg_writer(listen_events, table_identifier, checkpoint_path)
    query.awaitTermination()


if __name__ == "__main__":
    main()
