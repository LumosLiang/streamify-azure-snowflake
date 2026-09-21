# Engineering and generation rules

## Cross-component contracts

Before changing a value, trace it across producers and consumers:

| Contract | Producer | Consumers |
| --- | --- | --- |
| Kafka broker address | Azure VM/NIC plus `KAFKA_ADDRESS` | Kafka advertised listener, Spark submit/runtime |
| Spark master URL | Spark standalone master | workers and `spark-submit` |
| ADLS account/container | Terraform and runtime environment | Spark paths, Snowflake stage, documentation |
| Event topic/schema | Eventsim and `spark_streaming/schema.py` | Spark readers, Parquet columns, Snowflake staging SQL |
| Snowflake object names | `snowflake/*.sql` | Airflow SQL, connection, dbt profile and sources |
| dbt target | `dbt/profiles.yml` | Airflow dbt commands |
| Mounted paths | `airflow/docker-compose.yaml` | DAG Bash commands and dbt paths |

A configuration change is incomplete if a direct consumer still uses the old
contract. Avoid copying the same configuration into more places when an existing
environment variable or canonical file can remain the source.

## Terraform

- Keep Azure resources in `terraform/main.tf` and inputs in `variables.tf`;
  `terraform.tfvars.example` contains placeholders only.
- Use stable Terraform resource labels and clear Azure resource names. A resource
  label such as `azurerm_storage_container.iceberg` is Terraform-local; its
  `name` is the Azure object name.
- Scope RBAC to the narrowest resource that satisfies the active path. Document
  both identity and scope.
- Preserve the local `azure.tfstate` backend unless migration is explicitly
  requested. Never edit state by hand.
- Review the plan for replacement or deletion; a successful validation does not
  prove the plan is safe.

## Python and Spark

- Keep schemas explicit and maintain the current separation between schema,
  streaming utilities, and the entry script.
- Import modules in a way that works from the documented execution directory;
  check both imports and submit commands when moving files.
- Streaming jobs require durable checkpoints. Do not delete or reuse a checkpoint
  for a semantically different query without an explicit migration decision.
- Keep raw event writes append-only. Do not infer update/delete semantics from
  Eventsim unless a correction event model has been implemented.
- Avoid unrelated style rewrites in upstream learning code. Improve names or
  structure only when required by the task.

## Kafka and Docker Compose

- Kafka is KRaft-based. Do not reintroduce ZooKeeper.
- Maintain the distinction between Docker-internal listeners and the private VM
  listener advertised to Spark.
- Check whether a Compose change recreates containers and whether persistent
  volumes exist. State the data-loss implication before a recreate.
- Use `restart: unless-stopped` only for services intended to return after a VM
  restart; it does not start manually launched host processes or `spark-submit`.
- Keep `.env.example` values as placeholders and required-variable expressions
  explicit where startup without a value would be invalid.

## Airflow

- Airflow orchestrates; Snowflake SQL loads data and dbt builds models.
- Keep connection names, mounted `/opt/airflow/...` paths, and image entrypoints
  aligned with Compose.
- `docker compose run` inherits the Airflow image entrypoint unless overridden;
  commands such as dbt may require `--entrypoint dbt`.
- DAGs should be idempotent where practical, use explicit dependencies, and avoid
  overlapping runs for the same load path.
- Do not add maintenance DAGs during setup-only work.

## Snowflake and dbt

- Keep account bootstrap in `snowflake/setup.sql` and Azure external-stage setup
  in `snowflake/storage_setup.sql`.
- Use key-pair authentication for the dbt service user; do not place private keys
  or passphrases in repository files.
- `COPY INTO` staging behavior and deduplication must be reasoned separately from
  dbt model materialization. Do not claim that dbt declarations imply incremental
  behavior; models are incremental only when configured and written for it.
- Preserve `source()` for staging objects and `ref()` for model dependencies.
- When changing a model, check its grain, key, join cardinality, null behavior,
  history semantics, and downstream fact/wide model use.
- Format SQL consistently, but do not change business logic during formatting.

## Shell

- Use `#!/usr/bin/env bash` and `set -euo pipefail` for project scripts unless a
  sourced script requires different behavior.
- Resolve repository-relative paths from the script location.
- Quote expansions and use explicit allowlists for cloud resources.
- Provide `--dry-run` for scripts that change multiple remote resources when it
  materially improves reviewability.
- Never embed real environment values in scripts or documentation.

## Documentation

- Write natural, concise prose organized from architecture to operation.
- Explain why a setting exists when that prevents a likely misuse; omit chat
  history and one-off questions.
- For a reusable troubleshooting note, preserve the project context and the
  investigation path: what we were trying to do, what failed, which hypotheses
  were ruled out, what evidence identified the cause, and why the final fix was
  chosen. Do not reduce it to a detached symptom/root-cause template.
- Keep general credential-handling rules in `AGENTS.md`. Setup guides should
  state the required keys and where the process consumes them, without repeating
  generic warnings about committing `.env` files or command output.
- Put each fact in one canonical guide and link to it elsewhere.
- Commands must state where they run when Mac, Kafka VM, Airflow VM, and Spark VM
  could be confused.
- Keep current architecture separate from historical screenshots and future work.
- Update `.md` and `.en.md` pairs together while allowing natural phrasing rather
  than mechanical translation.
