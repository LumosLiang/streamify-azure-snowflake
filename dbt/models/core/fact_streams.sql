{{ config(materialized = 'table') }}

SELECT
    dim_users.userKey AS userKey,
    dim_artists.artistKey AS artistKey,
    dim_songs.songKey AS songKey,
    dim_datetime.dateKey AS dateKey,
    dim_location.locationKey AS locationKey,
    dim_user_agents.userAgentKey AS userAgentKey,
    listen_events.ts AS ts
FROM {{ source('staging', 'listen_events') }}
LEFT JOIN {{ ref('dim_users') }}
    ON listen_events.userId = dim_users.userId
    AND CAST(listen_events.ts AS DATE) >= dim_users.rowActivationDate
    AND CAST(listen_events.ts AS DATE) < dim_users.RowExpirationDate
LEFT JOIN {{ ref('dim_artists') }}
    ON REPLACE(REPLACE(listen_events.artist, '"', ''), CHR(92), '') = dim_artists.name
LEFT JOIN {{ ref('dim_songs') }}
    ON REPLACE(REPLACE(listen_events.artist, '"', ''), CHR(92), '') = dim_songs.artistName
    AND listen_events.song = dim_songs.title
LEFT JOIN {{ ref('dim_location') }}
    ON listen_events.city = dim_location.city
    AND listen_events.state = dim_location.stateCode
    AND listen_events.lat = dim_location.latitude
    AND listen_events.lon = dim_location.longitude
LEFT JOIN {{ ref('dim_datetime') }}
    ON dim_datetime.date = DATE_TRUNC('hour', listen_events.ts)
LEFT JOIN {{ ref('dim_user_agents') }}
    ON listen_events.userAgent = dim_user_agents.userAgent
