#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash create_principal.sh spark-writer <catalog> <principal> <principal-role> <catalog-role>
  bash create_principal.sh snowflake-reader <catalog> <principal> <principal-role> <catalog-role> <namespace>

Creates a dedicated Polaris principal using one of the supported permission
profiles. The generated client credentials are printed once after setup.
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

profile="$1"
shift

case "$profile" in
  spark-writer)
    if [[ $# -ne 4 ]]; then
      usage >&2
      exit 2
    fi
    catalog_name="$1"
    principal_name="$2"
    principal_role_name="$3"
    catalog_role_name="$4"
    namespace_name=""
    ;;
  snowflake-reader)
    if [[ $# -ne 5 ]]; then
      usage >&2
      exit 2
    fi
    catalog_name="$1"
    principal_name="$2"
    principal_role_name="$3"
    catalog_role_name="$4"
    namespace_name="$5"
    if ! [[ "$namespace_name" =~ ^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z][A-Za-z0-9_-]*)*$ ]]; then
      echo 'Namespace must be dot-separated names containing letters, digits, underscores, or hyphens.' >&2
      exit 2
    fi
    ;;
  *)
    echo "Unknown permission profile: ${profile}" >&2
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="${script_dir}/.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing ${env_file}. Create it from .env.example first." >&2
  exit 1
fi

for entity_name in "$catalog_name" "$principal_name" "$principal_role_name" "$catalog_role_name"; do
  if ! [[ "$entity_name" =~ ^[A-Za-z][A-Za-z0-9_-]{0,254}$ ]]; then
    echo 'Names must start with a letter and contain only letters, digits, underscores, or hyphens.' >&2
    exit 2
  fi
done

read_env_value() {
  local variable_name="$1"
  local line value=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${variable_name}="* ]]; then
      value="${line#*=}"
      break
    fi
  done < "$env_file"

  if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]] || \
    [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
    value="${value:1:${#value}-2}"
  fi

  if [[ -z "$value" || "$value" == '<'*'>' ]]; then
    echo "Missing ${variable_name} in ${env_file}." >&2
    exit 1
  fi

  printf '%s' "$value"
}

if command -v polaris >/dev/null; then
  polaris_cli="$(command -v polaris)"
elif [[ -x "$HOME/.local/bin/polaris" ]]; then
  polaris_cli="$HOME/.local/bin/polaris"
else
  echo 'The Polaris CLI is required. Install it with: sudo apt-get install -y pipx && pipx install apache-polaris' >&2
  exit 1
fi

polaris_client_id="$(read_env_value POLARIS_CLIENT_ID)"
polaris_client_secret="$(read_env_value POLARIS_CLIENT_SECRET)"

polaris_cmd() {
  "$polaris_cli" \
    --host 127.0.0.1 \
    --port 8181 \
    --client-id "$polaris_client_id" \
    --client-secret "$polaris_client_secret" \
    "$@"
}

if ! polaris_cmd catalogs get "$catalog_name" >/dev/null; then
  echo "Catalog ${catalog_name} was not found or Polaris is unavailable." >&2
  exit 1
fi

if [[ "$profile" == "snowflake-reader" ]] && \
  ! polaris_cmd namespaces get --catalog "$catalog_name" "$namespace_name" >/dev/null; then
  echo "Namespace ${namespace_name} was not found in catalog ${catalog_name}." >&2
  exit 1
fi

ensure_absent() {
  local description="$1"
  shift

  if polaris_cmd "$@" >/dev/null 2>&1; then
    echo "${description} already exists. No changes were made." >&2
    exit 1
  fi
}

ensure_absent "Principal ${principal_name}" principals get "$principal_name"
ensure_absent "Principal role ${principal_role_name}" principal-roles get "$principal_role_name"
ensure_absent "Catalog role ${catalog_role_name}" catalog-roles get --catalog "$catalog_name" "$catalog_role_name"

polaris_cmd principal-roles create "$principal_role_name"
polaris_cmd catalog-roles create --catalog "$catalog_name" "$catalog_role_name"
polaris_cmd catalog-roles grant \
  --catalog "$catalog_name" \
  --principal-role "$principal_role_name" \
  "$catalog_role_name"

if [[ "$profile" == "spark-writer" ]]; then
  polaris_cmd privileges catalog grant \
    --catalog "$catalog_name" \
    --catalog-role "$catalog_role_name" \
    CATALOG_MANAGE_CONTENT
else
  # Snowflake must discover catalog namespaces, but receives table access only
  # inside the namespace selected for this principal.
  polaris_cmd privileges catalog grant \
    --catalog "$catalog_name" \
    --catalog-role "$catalog_role_name" \
    CATALOG_READ_PROPERTIES
  polaris_cmd privileges catalog grant \
    --catalog "$catalog_name" \
    --catalog-role "$catalog_role_name" \
    NAMESPACE_LIST

  for privilege in NAMESPACE_READ_PROPERTIES TABLE_LIST TABLE_READ_PROPERTIES TABLE_READ_DATA; do
    polaris_cmd privileges namespace grant \
      --catalog "$catalog_name" \
      --catalog-role "$catalog_role_name" \
      --namespace "$namespace_name" \
      "$privilege"
  done
fi

principal_credentials="$(polaris_cmd principals create "$principal_name")"
polaris_cmd principal-roles grant \
  --principal "$principal_name" \
  "$principal_role_name"

printf '\nCreated %s principal %s with profile %s. Save these credentials for the configured client:\n%s\n' \
  "$profile" "$principal_name" "$profile" "$principal_credentials"

if [[ "$profile" == "spark-writer" ]]; then
  printf 'Granted CATALOG_MANAGE_CONTENT on catalog %s.\n' "$catalog_name"
else
  printf 'Granted read-only table access to namespace %s in catalog %s, including TABLE_READ_DATA.\n' \
    "$namespace_name" "$catalog_name"
fi
