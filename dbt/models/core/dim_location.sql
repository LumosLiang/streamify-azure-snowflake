{{ config(materialized = 'table') }}

SELECT
    {{ dbt_utils.generate_surrogate_key(['latitude', 'longitude', 'city', 'stateName']) }} AS locationKey,
    *
FROM (
    SELECT DISTINCT
        city,
        COALESCE(state_codes.stateCode, 'NA') AS stateCode,
        COALESCE(state_codes.stateName, 'NA') AS stateName,
        lat AS latitude,
        lon AS longitude
    FROM {{ source('staging', 'listen_events') }}
    LEFT JOIN {{ ref('state_codes') }}
        ON listen_events.state = state_codes.stateCode

    UNION ALL

    SELECT
        'NA',
        'NA',
        'NA',
        0.0,
        0.0
)
