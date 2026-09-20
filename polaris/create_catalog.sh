#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bash create_catalog.sh <storage-account-name> <container-name> <catalog-name> <base-path>

Creates an Azure-backed Polaris catalog. The catalog data location is:
  abfss://<container-name>@<storage-account-name>.dfs.core.windows.net/<base-path>/

The script requires .env in this directory with the Polaris root principal and
Azure service-principal values. It does not create a namespace or Iceberg table.
EOF
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 2
fi

storage_account="$1"
container_name="$2"
catalog_name="$3"
base_path="${4#/}"
base_path="${base_path%/}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
env_file="${script_dir}/.env"

if [[ ! -f "$env_file" ]]; then
  echo "Missing ${env_file}. Create it from .env.example first." >&2
  exit 1
fi

if ! [[ "$storage_account" =~ ^[a-z0-9]{3,24}$ ]]; then
  echo 'Storage account name must be 3-24 lowercase letters or digits.' >&2
  exit 2
fi

if ! [[ "$container_name" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]]; then
  echo 'Container name must be 3-63 lowercase letters, digits, or hyphens.' >&2
  exit 2
fi

if ! [[ "$catalog_name" =~ ^[A-Za-z][A-Za-z0-9_]{0,254}$ ]]; then
  echo 'Catalog name must start with a letter and contain only letters, digits, or underscores.' >&2
  exit 2
fi

if ! [[ "$base_path" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || \
  [[ "$base_path" == *'..'* || "$base_path" == *'//'* ]]; then
  echo 'Base path must be a non-empty relative path without .. or repeated slashes.' >&2
  exit 2
fi

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

polaris_client_id="$(read_env_value POLARIS_CLIENT_ID)"
polaris_client_secret="$(read_env_value POLARIS_CLIENT_SECRET)"
azure_tenant_id="$(read_env_value AZURE_TENANT_ID)"
read_env_value AZURE_CLIENT_ID >/dev/null
read_env_value AZURE_CLIENT_SECRET >/dev/null

for command_name in curl python3; do
  command -v "$command_name" >/dev/null || {
    echo "${command_name} is required." >&2
    exit 1
  }
done

polaris_base_url="http://127.0.0.1:8181"
base_location="abfss://${container_name}@${storage_account}.dfs.core.windows.net/${base_path}/"
allowed_location="abfss://${container_name}@${storage_account}.dfs.core.windows.net/"

polaris_token="$({
  curl --fail --silent --show-error \
    --user "${polaris_client_id}:${polaris_client_secret}" \
    -d 'grant_type=client_credentials' \
    -d 'scope=PRINCIPAL_ROLE:ALL' \
    "${polaris_base_url}/api/catalog/v1/oauth/tokens" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["access_token"])'
} )"

catalog_url="${polaris_base_url}/api/management/v1/catalogs/${catalog_name}"
existing_status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  --header "Authorization: Bearer ${polaris_token}" \
  "$catalog_url")"

case "$existing_status" in
  404) ;;
  200)
    echo "Catalog ${catalog_name} already exists. No changes were made." >&2
    exit 1
    ;;
  *)
    echo "Could not check catalog ${catalog_name} (HTTP ${existing_status})." >&2
    exit 1
    ;;
esac

curl --fail-with-body --silent --show-error \
  --request POST "${polaris_base_url}/api/management/v1/catalogs" \
  --header "Authorization: Bearer ${polaris_token}" \
  --header 'Content-Type: application/json' \
  --data "{
    \"catalog\": {
      \"type\": \"INTERNAL\",
      \"name\": \"${catalog_name}\",
      \"properties\": {
        \"default-base-location\": \"${base_location}\"
      },
      \"storageConfigInfo\": {
        \"storageType\": \"AZURE\",
        \"tenantId\": \"${azure_tenant_id}\",
        \"hierarchical\": true,
        \"allowedLocations\": [\"${allowed_location}\"]
      }
    }
  }"

printf '\nCatalog %s created.\n' "$catalog_name"
