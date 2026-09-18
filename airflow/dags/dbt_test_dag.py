from datetime import datetime

from airflow.sdk import DAG
from airflow.providers.standard.operators.bash import BashOperator


with DAG(
    dag_id="dbt_test",
    description="Compile the Streamify dbt project",
    schedule=None,
    start_date=datetime(2022, 3, 20),
    catchup=False,
    tags=["streamify", "dbt"],
) as dag:
   

    dbt_compile = BashOperator(
        task_id="dbt_compile",
        bash_command=(
            f"cd /opt/airflow/dbt && dbt deps && "
            "dbt compile --profiles-dir . --target prod"
        ),
    )

    dbt_compile

