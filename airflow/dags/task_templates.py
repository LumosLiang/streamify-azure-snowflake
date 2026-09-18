from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator


def copy_event_to_snowflake(event):
    """Create one task that loads an ADLS event prefix into Snowflake."""
    return SQLExecuteQueryOperator(
        task_id=f"copy_{event}_to_snowflake",
        conn_id="snowflake_default",
        sql=f"sql/{event}.sql",
    )
