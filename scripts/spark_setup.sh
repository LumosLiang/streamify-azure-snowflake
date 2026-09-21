#!/usr/bin/env bash
set -euo pipefail

SPARK_VERSION="${SPARK_VERSION:-4.1.3}"
SPARK_DIR="${HOME}/spark"
SPARK_HOME="${SPARK_DIR}/spark-${SPARK_VERSION}-bin-hadoop3"
SPARK_DOWNLOAD_BASE_URL="${SPARK_DOWNLOAD_BASE_URL:-https://archive.apache.org/dist/spark}"

echo "Installing Java 17..."
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk curl tar

echo "Installing Spark ${SPARK_VERSION}..."
mkdir -p "${SPARK_DIR}"
if [[ ! -d "${SPARK_HOME}" ]]; then
	tmp_archive="$(mktemp "${TMPDIR:-/tmp}/spark.XXXXXX.tgz")"
	trap 'rm -f "${tmp_archive}"' EXIT
	curl -fL --retry 3 --retry-delay 2 \
		"${SPARK_DOWNLOAD_BASE_URL}/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz" \
		-o "${tmp_archive}"
	tar -xzf "${tmp_archive}" -C "${SPARK_DIR}"
fi
PY4J_ZIP="$(find "${SPARK_HOME}/python/lib" -maxdepth 1 -name 'py4j-*.zip' -print -quit)"
if [[ -z "${PY4J_ZIP}" ]]; then
	echo "Could not find Spark's py4j zip file" >&2
	exit 1
fi

cat > "${HOME}/.spark_env" <<EOF
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
export SPARK_HOME="${SPARK_HOME}"
export PATH="\${JAVA_HOME}/bin:\${SPARK_HOME}/bin:\${SPARK_HOME}/sbin:\${PATH}"
export PYTHONPATH="\${SPARK_HOME}/python:${PY4J_ZIP}:\${PYTHONPATH:-}"
EOF

if ! grep -q 'source "$HOME/.spark_env"' "${HOME}/.bashrc"; then
	printf '\nsource "$HOME/.spark_env"\n' >> "${HOME}/.bashrc"
fi

source "${HOME}/.spark_env"

echo "Java: $(java -version 2>&1 | head -n 1)"
echo "Spark: ${SPARK_HOME}"
echo "Installation complete. Run this script on the master and both workers."