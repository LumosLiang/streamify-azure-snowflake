# Streamify agent entry point

This repository is a learning-oriented Azure/Snowflake rewrite of the original
GCP Streamify project. Work in small, reviewable steps and keep the current
working path intact while a new path is being learned or validated.

## Read before changing anything

1. Read [`.harness/project.md`](.harness/project.md) for the current architecture,
   implemented state, and deferred work.
2. Read [`.harness/workflow.md`](.harness/workflow.md) for scope and collaboration
   rules.
3. Read [`.harness/engineering.md`](.harness/engineering.md) before generating code
   or documentation.
4. Use [`.harness/verification.md`](.harness/verification.md) to select checks for
   the files changed.
5. Then inspect the nearest README/setup guide, implementation, and recent Git
   history for the component being changed.

Do not load every file by default. Follow the data flow only as far as the
current task requires.

## Current system boundary

The repository currently has two data paths:

```text
Eventsim -> Kafka -> Spark Structured Streaming -> ADLS Gen2 Parquet
                                                    -> Airflow -> Snowflake staging -> dbt

Kafka listen_events -> Spark Structured Streaming -> Polaris REST catalog
                                                     -> ADLS Gen2 Iceberg table
```

- Azure infrastructure is defined by Terraform: five VMs, network resources,
  managed identities, RBAC, and two ADLS Gen2 accounts.
- Kafka and Eventsim share the Kafka VM and run in Docker. Kafka uses KRaft.
- Spark is a manually installed standalone cluster: one master and two workers.
- The existing Parquet path is orchestrated by Airflow: Snowflake loads Parquet
  from Azure through a storage integration and external stage, then dbt builds
  models. This path remains intact.
- A parallel Spark Structured Streaming job writes Kafka `listen_events` into
  the Polaris-managed Iceberg table `streamify_raw.listen_events`. Its writes,
  checkpointing, and Spark SQL reads have been runtime-verified.
- Polaris and PostgreSQL run in Docker on the Spark Master VM. Polaris manages
  the Iceberg catalog and metadata; table files live in the separate
  `streamify-iceberg` ADLS Gen2 account. Streaming checkpoints use a separate
  container and are not part of the Iceberg table.
- Snowflake currently queries the Parquet path. The Snowflake REST catalog
  integration and public HTTPS route for Polaris are prepared but not yet
  deployed or runtime-verified. Do not describe Snowflake Iceberg reads as
  working until the catalog integration and a table query succeed.
- Airflow does not yet orchestrate the Iceberg streaming job or table
  maintenance. Compaction, snapshot expiration, and orphan-file cleanup remain
  deferred.

Never describe planned or partially configured work as operational.

## Non-negotiable working rules

- Make only the requested change. Do not add adjacent infrastructure,
  orchestration, persistence, maintenance, refactors, or "helpful" cleanup.
- Preserve the current working path and original learning code unless the user
  explicitly asks to replace or remove it.
- Prefer the smallest change close to the original project architecture.
- Explain the reason and impact of a change in plain Chinese before or while
  making it. The user wants to learn and performs important setup steps.
- Treat cloud mutations as user-run steps. Prepare and validate the code, then
  give the exact command; do not run `terraform apply/destroy`, Azure resource
  mutations, Snowflake setup SQL, or live deployment commands without an
  explicit request.
- Never broaden a resource operation. VM scripts must keep an explicit project
  allowlist and must not enumerate and mutate an entire subscription.
- Do not overwrite or discard uncommitted work. Inspect `git status` and the
  relevant diff first.
- Do not commit, push, rewrite history, or open a PR unless requested.

## Privacy and credentials

- Never expose or commit real IPs, subscription/account/tenant/object IDs,
  storage account names, usernames, passwords, private keys, tokens, or generated
  Snowflake/Polaris credentials. Use `<placeholder>` values in documentation.
- Treat `*.tfstate`, `terraform.tfvars`, `.env`, SSH configuration, and command
  output from live accounts as sensitive. Avoid reading or printing them unless
  the task explicitly requires it.
- `airflow/.env` is currently tracked. Do not assume tracked means safe, expose
  its contents, or change its tracking status unless explicitly requested.
- Prefer managed identity or scoped service principals. Apply least privilege
  and state the scope of every RBAC grant.
- Before finishing, check that examples and diffs contain no environment-specific
  values.

## Source of truth

When sources disagree, use this order:

1. Current executable code and configuration.
2. A verified runtime result supplied by the user.
3. Current setup documentation.
4. Recent project Git history and commit intent.
5. Conversation context and the original GCP project.

Version-sensitive behavior must be checked against official documentation.
Record uncertainty as `待验证`; do not invent a successful runtime result.

## Change workflow

1. Restate the exact component and boundary internally.
2. Trace its inputs, outputs, identity, storage path, runtime, and callers.
3. Check current code, documentation, `git status`, and the relevant history.
4. Change the minimum coherent set of files.
5. Run the narrowest meaningful static check, then the component check if it is
   local and non-destructive.
6. Review the diff for scope, secrets, stale GCP assumptions, and documentation
   drift.
7. Report what changed, why, validation performed, and what remains unverified.

## Documentation rules

- Keep repository docs project-focused; do not preserve chat Q&A, personal
  confusion, one-off exercises, or troubleshooting diaries.
- README explains architecture and navigation. `setup/` explains deployment by
  component. `snowflake/` owns Snowflake setup. Keep details in one canonical
  location and link to it instead of duplicating it.
- When changing an existing bilingual README or setup guide, update both Chinese
  and English versions in the same change.
- Distinguish clearly among implemented and verified, configured but unverified,
  and deferred.

## Completion standard

A change is complete only when it is scoped, internally consistent, free of
secrets, accompanied by the necessary canonical documentation, and checked with
the applicable commands in `.harness/verification.md`. Live cloud behavior is
not "verified" unless it was actually run and observed.
