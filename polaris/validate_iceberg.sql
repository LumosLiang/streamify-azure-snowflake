CREATE NAMESPACE IF NOT EXISTS polaris.validation;

CREATE TABLE IF NOT EXISTS polaris.validation.spark_connectivity (
  id BIGINT,
  message STRING
)
USING iceberg;

INSERT INTO polaris.validation.spark_connectivity
SELECT 1, 'polaris-iceberg'
WHERE NOT EXISTS (
  SELECT 1
  FROM polaris.validation.spark_connectivity
  WHERE id = 1
);

SELECT id, message
FROM polaris.validation.spark_connectivity
ORDER BY id;
