# Verification matrix

Run checks that match the changed files. Start narrow; do not run live cloud or
data-changing checks merely to make the list look complete.

## Always

```bash
git status --short
git diff --check
git diff -- <changed-paths>
```

Review the diff for:

- accidental changes outside scope;
- real identifiers, IPs, credentials, keys, or account output;
- stale GCP/BigQuery/GCS/Dataproc assumptions in current-path docs;
- claims that configured or planned behavior was runtime verified;
- a changed Chinese setup/README without its English counterpart.
- generic personal reminders about committing `.env`, credentials, or command
  output that belong in `AGENTS.md` rather than project-facing documentation.

Do not print `terraform.tfvars`, `.env`, state files, private keys, or live account
configuration during this review.

## Terraform

```bash
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate -no-color
```

The user runs `terraform plan` and reviews replacements/deletions before apply.
An agent may analyze a supplied plan, but must not infer plan safety from
`validate`.

## Python and Airflow DAGs

For syntax without executing imports or external connections:

```bash
python3 -m py_compile <changed-python-files>
```

When Airflow is already running and the user requests runtime validation, prefer
container-local checks documented in `setup/airflow.md`. Do not start the full
stack solely for a static edit.

## Shell

```bash
bash -n <changed-shell-files>
```

For `scripts/bulk_operate_vm.sh`, use `--dry-run` only when the user asks for a
live Azure check. Confirm the active subscription and the five-name allowlist;
never replace it with subscription-wide discovery.

## Docker Compose

With non-secret placeholder variables where required:

```bash
docker compose -f <compose-file> config --quiet
```

Do not use `up`, `down`, `down -v`, or image pulls as a formatting check. Explain
container recreation and volume effects before a user-run deployment.

## dbt and SQL

Preferred checks run inside the existing Airflow image because dbt is installed
there:

```bash
docker compose -f airflow/docker-compose.yaml run --rm \
  --entrypoint dbt airflow-worker --version
docker compose -f airflow/docker-compose.yaml run --rm \
  --entrypoint dbt airflow-worker compile \
  --project-dir /opt/airflow/dbt --profiles-dir /opt/airflow/dbt --target prod
```

Compilation may require credentials and a running Compose dependency set. If it
cannot be run safely, report it as not run; do not substitute visual SQL review
and call it validated.

Before a model change is accepted, trace:

```text
Snowflake staging columns -> dbt source -> model grain/keys -> downstream refs
```

## Markdown and links

Use `rg` to confirm renamed paths and referenced commands. Check relative links
for every changed document and compare the Chinese/English pair for factual
parity. Do not duplicate a setup block that already has a canonical home.

## Runtime evidence

Record exactly what was observed: command, target component, and outcome. Examples
of insufficient evidence:

- Polaris health `UP` does not prove ADLS access.
- Kafka container `running` does not prove Spark can use its advertised listener.
- Spark master UI does not prove a streaming application is durable.
- Visible Parquet files do not prove Snowflake loaded every logical event once.
- A successful Airflow DAG does not by itself prove dimensional joins preserve
  the intended grain.
