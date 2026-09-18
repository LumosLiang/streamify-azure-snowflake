-- 从 listen_events 构建 userAgent 维度：每个不同的 userAgent 一行，
-- 输出 userAgentKey 和 userAgent；可以参考其他维度的代理键写法。
-- Write the SELECT and then remove enabled=false.
-- 写完 SELECT 后删除 enabled=false。
-- Later, add userAgentKey to fact_streams by joining this dimension on userAgent.
-- 下一步再按 userAgent 关联本维度，把 userAgentKey 加入 fact_streams。

SELECT
    {{ dbt_utils.generate_surrogate_key(['userAgent']) }} AS userAgentKey,
    *
FROM (
    (
        SELECT DISTINCT
            userAgent
        FROM {{ source('staging', 'listen_events') }}
    )

    UNION ALL

    (
        SELECT
            'NA'
    )
    
)
