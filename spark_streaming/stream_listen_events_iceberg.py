"""A parallel Kafka-to-Iceberg streaming job for listen_events.

It must not replace or modify stream_all_events.py, which continues to write
the existing Parquet path. The Iceberg checkpoint container and its Spark VM
managed-identity access must exist before this job is submitted.
"""

from iceberg_config import (
    CATALOG_ALIAS,
    LISTEN_EVENTS_TOPIC,
    StreamingConfig,
    build_streaming_config,
)
from schema import schema
from streaming_utils import create_kafka_read_stream, create_or_get_spark_session, process_stream


KAFKA_PORT = "9092"


def build_spark_session(config: StreamingConfig):
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
        f"{catalog_prefix}.warehouse": config.polaris_catalog_name,
        f"{catalog_prefix}.scope": "PRINCIPAL_ROLE:ALL",
        f"{catalog_prefix}.credential": (
            f"{config.polaris_client_id}:{config.polaris_client_secret}"
        ),
        f"{catalog_prefix}.header.X-Iceberg-Access-Delegation": "vended-credentials",
        f"{catalog_prefix}.io-impl": "org.apache.iceberg.azure.adlsv2.ADLSFileIO",
    }
    return create_or_get_spark_session(
        "Eventsim Listen Events to Iceberg",
        storage_account=config.checkpoint_storage_account,
        extra_configs=catalog_configs,
    )


def build_listen_events_stream(spark, config: StreamingConfig):
    """Create a DataStreamReader for listen_events with the normalized schema."""

    listen_events = create_kafka_read_stream(
        spark, config.kafka_address, KAFKA_PORT, LISTEN_EVENTS_TOPIC
    )
    listen_events = process_stream(
        listen_events, schema[LISTEN_EVENTS_TOPIC], LISTEN_EVENTS_TOPIC
    )
    return listen_events


def ensure_listen_events_table(spark, config: StreamingConfig):
    """Create the Polaris namespace and Iceberg table for normalized listens."""
    namespace_identifier = ".".join(config.table_identifier.split(".")[:-1])

    spark.sql(f"CREATE NAMESPACE IF NOT EXISTS {namespace_identifier}")
    spark.sql(
        f"""
        CREATE TABLE IF NOT EXISTS {config.table_identifier} (
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

def start_iceberg_writer(stream, config: StreamingConfig):
    """Start a streaming query that writes to the Iceberg table."""
    iceberg_write_stream_query = (
        stream.writeStream
        .format("iceberg")
        .outputMode("append")
        .trigger(processingTime="1 minute")
        .option("checkpointLocation", config.checkpoint_path)
        .toTable(config.table_identifier)
    )

    return iceberg_write_stream_query


def main():
    config = build_streaming_config()
    spark = build_spark_session(config)

    ensure_listen_events_table(spark, config)
    listen_events = build_listen_events_stream(spark, config)
    query = start_iceberg_writer(listen_events, config)
    query.awaitTermination()


if __name__ == "__main__":
    main()
