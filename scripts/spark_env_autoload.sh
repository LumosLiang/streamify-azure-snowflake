#!/usr/bin/env bash
set -euo pipefail

bashrc_file="${HOME}/.bashrc"
marker="# Streamify Spark job environment files"

touch "${bashrc_file}"

if ! grep -Fqx "${marker}" "${bashrc_file}"; then
	cat >> "${bashrc_file}" <<'EOF'

# Streamify Spark job environment files
for streamify_env_file in "$HOME"/.config/streamify/spark-*.env; do
	[[ -f "$streamify_env_file" ]] && source "$streamify_env_file"
done
unset streamify_env_file
EOF
fi

echo "Spark job environment files will load in new interactive Bash sessions."
