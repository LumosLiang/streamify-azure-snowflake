"""Runtime configuration for the Kafka-to-Iceberg streaming job."""

import os
from dataclasses import dataclass


LISTEN_EVENTS_TOPIC = "listen_events"
CATALOG_ALIAS = "polaris"


@dataclass(frozen=True)
class StreamingConfig:
    """Runtime values collected once at the edge of the application."""

    kafka_address: str
    checkpoint_storage_account: str
    checkpoint_container: str
    polaris_client_id: str
    polaris_client_secret: str
    polaris_catalog_name: str
    namespace: str
    table_name: str

    @property
    def table_identifier(self):
        """Return the three-part Iceberg identifier used by Spark."""
        return f"{CATALOG_ALIAS}.{self.namespace}.{self.table_name}"

    @property
    def checkpoint_path(self):
        """Return the checkpoint path outside the Polaris-managed table data."""
        return (
            f"abfss://{self.checkpoint_container}@"
            f"{self.checkpoint_storage_account}.dfs.core.windows.net/"
            f"checkpoint/iceberg/{self.table_name}"
        )


def require_env(variable_name):
    """Return a required environment variable with a clear startup error."""
    value = os.getenv(variable_name)
    if not value:
        raise RuntimeError(f"Set {variable_name} before submitting this job.")
    return value


def build_streaming_config():
    """Read process environment once and construct explicit runtime configuration."""
    return StreamingConfig(
        kafka_address=require_env("KAFKA_ADDRESS"),
        checkpoint_storage_account=require_env("ICEBERG_CHECKPOINT_STORAGE_ACCOUNT"),
        checkpoint_container=os.getenv("ICEBERG_CHECKPOINT_CONTAINER", "streamify-checkpoints"),
        polaris_client_id=require_env("POLARIS_SPARK_CLIENT_ID"),
        polaris_client_secret=require_env("POLARIS_SPARK_CLIENT_SECRET"),
        polaris_catalog_name=require_env("POLARIS_CATALOG_NAME"),
        namespace=os.getenv("ICEBERG_NAMESPACE", "streamify_raw"),
        table_name=os.getenv("ICEBERG_TABLE", LISTEN_EVENTS_TOPIC),
    )
