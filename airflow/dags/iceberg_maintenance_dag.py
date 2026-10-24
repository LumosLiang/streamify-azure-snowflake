from datetime import datetime, timezone

from airflow.sdk import DAG
from airflow.providers.ssh.operators.ssh import SSHOperator


SPARK_REPOSITORY = "streamify-azure-snowflake"
REMOTE_SCRIPT = "scripts/spark_iceberg_maintenance.sh"


def run_spark_iceberg_maintenance(operation):
    return SSHOperator(
        task_id=f"{operation}_listen_events_iceberg",
        ssh_conn_id="spark_master_ssh",
        command=(
            "bash -lc "
            f"'cd \"$HOME/{SPARK_REPOSITORY}\" && "
            f"bash {REMOTE_SCRIPT} {operation}'"
        ),
        conn_timeout=30,
        cmd_timeout=3600,
        get_pty=True,
        retries=1,
    )


with DAG(
    dag_id="iceberg_maintenance_dag",
    description="Compact Iceberg data files and retain seven days of snapshots",
    schedule="0 3 * * *",
    start_date=datetime(2026, 9, 27, tzinfo=timezone.utc),
    catchup=False,
    max_active_runs=1,
    is_paused_upon_creation=True,
    tags=["streamify", "iceberg"],
) as dag:
    compact_table = run_spark_iceberg_maintenance("compact")
    expire_snapshots = run_spark_iceberg_maintenance("expire")

    compact_table >> expire_snapshots
