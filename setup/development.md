# 本地 Python 开发环境

中文 | [English](development.en.md)

在 Mac 的项目根目录运行。环境使用 Python 3.12，PySpark 固定为集群使用的 4.1.3；`kafka-python` 供 Kafka 测试程序使用，pytest 用于本地测试。

```bash
brew install uv
uv sync --locked
uv run python -c 'import pyspark; print(pyspark.__version__)'
uv run pytest
```

版本检查应输出 `4.1.3`，测试应全部通过。`uv sync` 创建根目录下的 `.venv`；在 VS Code 的 **Python: Select Interpreter** 中选择 `.venv/bin/python`，即可使用该环境阅读、补全和调试 Python 代码。`uv run` 使用项目环境，无需手动激活。

`pyproject.toml` 声明依赖与测试配置，`uv.lock` 固定解析结果，`.python-version` 选择 Python 3.12。修改依赖后运行 `uv lock`，其他环境用 `uv sync --locked` 安装同一组版本。

这里只安装 Spark 代码的开发依赖。Airflow、dbt 与 provider 依赖继续由 `airflow/requirements.txt` 和 Dockerfile 管理，使用方式见 [Airflow](airflow.md) 和 [dbt](dbt.md)。

导入 PySpark 和运行配置测试不需要连接集群。本地真正运行 Spark 还需要 Java 17 或 21；本地 `.venv` 不会自动分发给 Azure workers。VM 上继续按 [Spark 部署](spark.md) 使用现有安装与作业配置。`uv run` 不会读取宿主机的 Spark profile 或云端凭据。

参考：[uv 项目结构](https://docs.astral.sh/uv/concepts/projects/layout/)、[依赖锁定与同步](https://docs.astral.sh/uv/concepts/projects/sync/)、[Spark 4.1.3 运行要求](https://spark.apache.org/docs/4.1.3/)。
