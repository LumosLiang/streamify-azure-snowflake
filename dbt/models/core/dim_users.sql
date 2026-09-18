{{ config(materialized = 'table') }}

-- level column in the users dimension is considered to be a SCD2 change. Just for the purpose of learning to write SCD2 change queries.
-- The below query is constructed to accommodate changing levels from free to paid and maintaining the latest state of the user along with
-- historical record of the user's level

SELECT
    {{ dbt_utils.generate_surrogate_key(['userId', 'rowActivationDate', 'level']) }} AS userKey,
    *
FROM (
    SELECT
        CAST(userId AS BIGINT) AS userId,
        firstName,
        lastName,
        gender,
        level,
        CAST(registration AS BIGINT) AS registration,
        minDate AS rowActivationDate,
        -- Choose the start date from the next record and add that as the expiration date for the current record
        LEAD(minDate, 1, '9999-12-31') OVER (
            PARTITION BY userId, firstName, lastName, gender
            ORDER BY grouped
        ) AS rowExpirationDate,
        -- Assign a flag indicating which is the latest row for easier select queries
        CASE
            WHEN RANK() OVER (
                PARTITION BY userId, firstName, lastName, gender
                ORDER BY grouped DESC
            ) = 1 THEN 1
            ELSE 0
        END AS currentRow
    FROM (
        -- Find the earliest date available for each free/paid status change
        SELECT
            userId,
            firstName,
            lastName,
            gender,
            registration,
            level,
            grouped,
            CAST(MIN(date) AS DATE) AS minDate
        FROM (
            -- Create distinct group of each level change to identify the change in level accurately
            SELECT
                *,
                SUM(lagged) OVER (
                    PARTITION BY userId, firstName, lastName, gender
                    ORDER BY date
                ) AS grouped
            FROM (
                -- Lag the level and see where the user changes level from free to paid or otherwise
                SELECT
                    *,
                    CASE
                        WHEN LAG(level, 1, 'NA') OVER (
                            PARTITION BY userId, firstName, lastName, gender
                            ORDER BY date
                        ) <> level THEN 1
                        ELSE 0
                    END AS lagged
                FROM (
                    -- Select distinct state of user in each timestamp
                    SELECT DISTINCT
                        userId,
                        firstName,
                        lastName,
                        gender,
                        registration,
                        level,
                        ts AS date
                    FROM {{ source('staging', 'listen_events') }}
                    WHERE userId <> 0
                )
            )
        )
        GROUP BY userId, firstName, lastName, gender, registration, level, grouped
    )

    UNION ALL

    SELECT
        CAST(userId AS BIGINT) AS userKey,
        firstName,
        lastName,
        gender,
        level,
        CAST(registration AS BIGINT) AS registration,
        CAST(MIN(ts) AS DATE) AS rowActivationDate,
        DATE '9999-12-31' AS rowExpirationDate,
        1 AS currentRow
    FROM {{ source('staging', 'listen_events') }}
    WHERE userId = 0 OR userId = 1
    GROUP BY userId, firstName, lastName, gender, level, registration
)
