{{ config(materialized = 'table') }}

SELECT
    {{ dbt_utils.generate_surrogate_key(['songId']) }} AS songKey,
    *
FROM (
    (
        SELECT
            song_id AS songId,
            REPLACE(REPLACE(artist_name, '"', ''), CHR(92), '') AS artistName,
            duration,
            key,
            key_confidence AS keyConfidence,
            loudness,
            song_hotttnesss AS songHotness,
            tempo,
            title,
            year
        FROM {{ source('staging', 'songs') }}
    )

    UNION ALL

    (
        SELECT
            'NNNNNNNNNNNNNNNNNNN',
            'NA',
            0,
            -1,
            -1,
            -1,
            -1,
            -1,
            'NA',
            0
    )
)
