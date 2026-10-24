# Local Python development

[中文](development.md) | English

Run from the repository root on your Mac. The environment uses Python 3.12 and PySpark 4.1.3, matching the cluster. `kafka-python` supports the Kafka test producer; pytest runs local tests.

```bash
brew install uv
uv sync --locked
uv run python -c 'import pyspark; print(pyspark.__version__)'
uv run pytest
```

The version check should print `4.1.3`, and all tests should pass. `uv sync` creates `.venv` at the repository root. Select `.venv/bin/python` through **Python: Select Interpreter** in VS Code for navigation, completion, and debugging. `uv run` uses this environment without manual activation.

`pyproject.toml` declares dependencies and test settings, `uv.lock` records resolved versions, and `.python-version` selects Python 3.12. After changing dependencies, run `uv lock`; use `uv sync --locked` elsewhere to install the recorded versions.

This environment contains Spark development dependencies. Airflow, dbt, and their providers remain managed by `airflow/requirements.txt` and the Dockerfile. See [Airflow](airflow.en.md) and [dbt](dbt.en.md) for those environments.

Importing PySpark and running configuration tests does not require a cluster. Running Spark locally also requires Java 17 or 21. The local `.venv` is not distributed to Azure workers; keep using the existing installation and job profiles described in [Spark setup](spark.en.md). `uv run` does not load host Spark profiles or cloud credentials.

References: [uv project layout](https://docs.astral.sh/uv/concepts/projects/layout/), [locking and syncing](https://docs.astral.sh/uv/concepts/projects/sync/), and [Spark 4.1.3 requirements](https://spark.apache.org/docs/4.1.3/).
