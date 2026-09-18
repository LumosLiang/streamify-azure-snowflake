{{ config(materialized = 'table') }}

WITH date_series AS (
    SELECT
        DATEADD(
            hour,
            ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1,
            '2018-10-01'::TIMESTAMP_NTZ
        ) AS date
    FROM TABLE(GENERATOR(ROWCOUNT => 100000))
)

SELECT
    DATEDIFF(second, '1970-01-01'::TIMESTAMP_NTZ, date) AS dateKey,
    date,
    DAYOFWEEKISO(date) AS dayOfWeek,
    DAY(date) AS dayOfMonth,
    WEEKOFYEAR(date) AS weekOfYear,
    MONTH(date) AS month,
    YEAR(date) AS year,
    DAYOFWEEKISO(date) IN (6, 7) AS weekendFlag
FROM date_series
WHERE date < DATEADD(day, 1, CURRENT_DATE)
