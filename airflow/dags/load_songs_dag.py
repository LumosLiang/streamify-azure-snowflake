from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator


with DAG(
    dag_id="load_songs_dag",
    description="Load the bundled songs seed into Snowflake",
    schedule=None,
    start_date=datetime(2022, 3, 20),
    catchup=False,
    tags=["streamify", "dbt"],
) as dag:
    load_songs = BashOperator(
        task_id="dbt_seed_songs",
        bash_command=(
            "cd /opt/airflow/dbt && dbt deps && "
            "dbt seed --select songs --profiles-dir . --target dev"
        ),
    )
