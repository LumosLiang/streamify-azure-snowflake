import pytest

from iceberg_config import build_streaming_config


@pytest.fixture
def runtime_env(monkeypatch):
    for key in (
        "POLARIS_URI", "POLARIS_OAUTH2_URI", "ICEBERG_NAMESPACE",
        "ICEBERG_TABLE", "ICEBERG_CHECKPOINT_CONTAINER",
    ):
        monkeypatch.delenv(key, raising=False)
    for key, value in {
        "KAFKA_ADDRESS": "broker.example.test",
        "ICEBERG_CHECKPOINT_STORAGE_ACCOUNT": "exampleaccount",
        "POLARIS_SPARK_CLIENT_ID": "example-client",
        "POLARIS_SPARK_CLIENT_SECRET": "example-secret",
        "POLARIS_CATALOG_NAME": "example_catalog",
    }.items():
        monkeypatch.setenv(key, value)


def test_existing_profile_keeps_table_and_checkpoint_locations(runtime_env):
    config = build_streaming_config()
    assert config.table_identifier == "polaris.streamify_raw.listen_events"
    assert config.checkpoint_path == (
        "abfss://streamify-checkpoints@exampleaccount.dfs.core.windows.net/"
        "checkpoint/iceberg/listen_events"
    )
    assert config.polaris_uri == "http://127.0.0.1:8181/api/catalog"


def test_changing_catalog_endpoint_also_changes_default_token_endpoint(runtime_env, monkeypatch):
    monkeypatch.setenv("POLARIS_URI", "https://catalog.example.test/api/catalog/")
    config = build_streaming_config()
    assert config.polaris_uri == "https://catalog.example.test/api/catalog"
    assert config.polaris_oauth2_uri == "https://catalog.example.test/api/catalog/v1/oauth/tokens"


def test_separate_token_endpoint_can_be_configured(runtime_env, monkeypatch):
    monkeypatch.setenv("POLARIS_OAUTH2_URI", "https://auth.example.test/token")
    assert build_streaming_config().polaris_oauth2_uri == "https://auth.example.test/token"


def test_missing_credentials_fail_before_spark_starts(runtime_env, monkeypatch):
    monkeypatch.delenv("POLARIS_SPARK_CLIENT_SECRET")
    with pytest.raises(RuntimeError, match="POLARIS_SPARK_CLIENT_SECRET"):
        build_streaming_config()
