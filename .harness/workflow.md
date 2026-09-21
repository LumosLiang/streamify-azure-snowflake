# Agent operating model

## Default collaboration style

Answer and work in the smallest sufficient unit. Lead with the concrete result,
explain the causal reason, and stop when the requested component is complete.
Avoid broad option lists, generic tutorials, and completeness-driven additions.

The user prefers to understand and execute important setup steps. For a cloud or
runtime task, prepare a reviewable change and teach the next command rather than
silently operating the environment.

## Scope gate

Before editing, define four things:

1. **Component** — Terraform, Kafka, Spark, Snowflake, Airflow, dbt, or Polaris.
2. **Stage** — setup, validation, data flow, modeling, or maintenance.
3. **Requested artifact** — code, configuration, documentation, or explanation.
4. **Explicit exclusions** — especially later integrations and automation.

If the request is clear, proceed without asking. Mention a later dependency only
when it changes the present design. Do not implement it until requested.

Examples:

- Adding an ADLS container does not authorize a Spark writer or catalog.
- Validating one Iceberg table does not authorize a streaming Iceberg writer or
  maintenance DAGs.
- Updating Airflow setup does not authorize rewriting DAG business logic.
- A remembered convenience idea is not authorization to persist it.

## Repository inspection pattern

Use this order for a component task:

1. `git status --short` and the relevant uncommitted diff.
2. The component's Chinese setup guide and its English pair.
3. The executable files named by that guide.
4. Direct callers and consumers, following data and configuration values.
5. `git log -- <paths>` and focused `git show` when intent is unclear.
6. Official product documentation for current/version-sensitive behavior.

Use `rg`/`rg --files` for discovery. Do not scan secrets or generated directories
just to appear thorough.

## Change policy

- Patch the minimum coherent set. A coherent change may include code plus its
  canonical bilingual documentation.
- Preserve user-written learning files and incomplete exercises. Review them when
  asked; do not finish, relocate, or rename them automatically.
- Preserve upstream attribution and Git history.
- Prefer explicit names and ordinary control flow. This repository is read for
  learning, so avoid unnecessary abstraction.
- Do not upgrade unrelated dependencies while changing behavior. When an upgrade
  is requested, use a current stable compatible version and cite the source used
  to choose it.
- Do not repair an unrelated bug discovered during scoped work. Report it briefly
  if it materially affects the requested change.

## User-run operations

Default to giving the user these operations after preparing the files:

- `terraform plan`, `apply`, `destroy`, import, state operations;
- Azure RBAC/service-principal/resource mutations;
- Snowflake account-level SQL and credential changes;
- live VM start/stop, package installation, service deployment, and data deletion;
- commands that reveal account-specific values.

Static local checks are agent-run. Read-only inspection can be agent-run when it
does not expose secrets. If the user explicitly asks the agent to perform a live
operation, show the exact target and scope first and use the narrowest command.

## Status language

Use precise labels:

- **Implemented**: present in code/configuration.
- **Statically validated**: format, parse, compile, or local validation passed.
- **User verified**: the user supplied a successful runtime observation.
- **Runtime verified**: the agent ran the exact operation and observed success.
- **Configured,待验证**: configuration exists but its external behavior is not
  confirmed.
- **Deferred**: discussed or planned, absent from the active path.

Never turn a health endpoint into proof of downstream storage access, or a valid
Terraform configuration into proof that Azure resources were applied.

## Final response

Keep it short and reviewable:

1. What changed.
2. Why it changed.
3. What was checked.
4. The single next user-run step, only when one is needed.

Call out unverified external behavior. Do not repeat a long plan or list every
unchanged file.
