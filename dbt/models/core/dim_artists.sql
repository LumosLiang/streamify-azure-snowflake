{{ config(materialized = 'table') }}

SELECT
    {{ dbt_utils.generate_surrogate_key(['artistId']) }} AS artistKey,
    *
FROM (
    SELECT
        MAX(artist_id) AS artistId,
        MAX(artist_latitude) AS latitude,
        MAX(artist_longitude) AS longitude,
        MAX(artist_location) AS location,
        REPLACE(REPLACE(artist_name, '"', ''), CHR(92), '') AS name
    FROM {{ source('staging', 'songs') }}
    GROUP BY artist_name

    UNION ALL

    SELECT
        'NNNNNNNNNNNNNNN',
        0,
        0,
        'NA',
        'NA'
)
