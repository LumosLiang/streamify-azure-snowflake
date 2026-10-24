#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "Usage: $0 {compact|expire}" >&2
}

if [[ $# -ne 1 ]]; then
	usage
	exit 2
fi

for env_file in \
	"${HOME}/.spark_env" \
	"${HOME}/.polaris_spark.env" \
	"${HOME}/.config/streamify/spark-iceberg.env"; do
	if [[ -f "${env_file}" ]]; then
		source "${env_file}"
	fi
done

: "${SPARK_HOME:?Spark environment is not configured}"
: "${SPARK_MASTER_URL:?Spark master URL is not configured}"
: "${POLARIS_SPARK_CLIENT_ID:?Polaris Spark principal ID is not configured}"
: "${POLARIS_SPARK_CLIENT_SECRET:?Polaris Spark principal secret is not configured}"
: "${POLARIS_CATALOG_NAME:?Polaris catalog name is not configured}"

polaris_uri="${POLARIS_URI:-http://127.0.0.1:8181/api/catalog}"
polaris_uri="${polaris_uri%/}"
polaris_oauth2_uri="${POLARIS_OAUTH2_URI:-${polaris_uri}/v1/oauth/tokens}"

table_identifier="polaris.${ICEBERG_NAMESPACE:-streamify_raw}.${ICEBERG_TABLE:-listen_events}"

case "$1" in
	compact)
		sql="CALL polaris.system.rewrite_data_files(
  				table => '${table_identifier}'
			);"
		;;
	expire)
		# Spark SQL interprets this literal in UTC (see session.timeZone below).
		cutoff="$(python3 -c '
from datetime import datetime, timedelta, timezone
print((datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%d %H:%M:%S"))
')"
		sql="CALL polaris.system.expire_snapshots(
  				table => '${table_identifier}',
  				older_than => TIMESTAMP '${cutoff}',
  				retain_last => 1
			);"
		;;
	*)
		usage
		exit 2
		;;
esac

"${SPARK_HOME}/bin/spark-sql" \
	--master "${SPARK_MASTER_URL}" \
	--packages org.apache.iceberg:iceberg-spark-runtime-4.1_2.13:1.11.0,org.apache.iceberg:iceberg-azure-bundle:1.11.0 \
	--conf spark.sql.session.timeZone=UTC \
	--conf spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions \
	--conf spark.sql.catalog.polaris=org.apache.iceberg.spark.SparkCatalog \
	--conf spark.sql.catalog.polaris.type=rest \
	--conf "spark.sql.catalog.polaris.uri=${polaris_uri}" \
	--conf "spark.sql.catalog.polaris.oauth2-server-uri=${polaris_oauth2_uri}" \
	--conf spark.sql.catalog.polaris.token-refresh-enabled=false \
	--conf "spark.sql.catalog.polaris.warehouse=${POLARIS_CATALOG_NAME}" \
	--conf spark.sql.catalog.polaris.scope=PRINCIPAL_ROLE:ALL \
	--conf "spark.sql.catalog.polaris.credential=${POLARIS_SPARK_CLIENT_ID}:${POLARIS_SPARK_CLIENT_SECRET}" \
	--conf spark.sql.catalog.polaris.header.X-Iceberg-Access-Delegation=vended-credentials \
	--conf spark.sql.catalog.polaris.io-impl=org.apache.iceberg.azure.adlsv2.ADLSFileIO \
	-e "${sql}"
