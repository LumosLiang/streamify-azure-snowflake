from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator

from task_templates import copy_event_to_snowflake


EVENTS = ["listen_events", "page_view_events", "auth_events"]
DBT_DIR = "/opt/airflow/dbt"

default_args = {"owner": "airflow"}

with DAG(
    dag_id="streamify_dag",
    default_args=default_args,
    description="Load ADLS events into Snowflake and build dbt models",
    schedule="5 * * * *",
    start_date=datetime(2026, 9, 13, 17),
    catchup=False,
    max_active_runs=1,
    tags=["streamify"],
) as dag:
    copy_tasks = [copy_event_to_snowflake(event) for event in EVENTS]

    seed_state_codes = BashOperator(
        task_id="dbt_seed_state_codes",
        bash_command=(
            f"cd {DBT_DIR} && dbt deps && "
            "dbt seed --select state_codes --profiles-dir . --target prod"
        ),
    )

    run_dbt_models = BashOperator(
        task_id="dbt_run",
        bash_command=f"cd {DBT_DIR} && dbt run --profiles-dir . --target prod",
    )

    for copy_task in copy_tasks:
        copy_task >> seed_state_codes

    seed_state_codes >> run_dbt_models
