-- Check that gross margin equals costed revenue minus cost
SELECT *
FROM {{ ref('weekly_margin') }}
WHERE ABS(
    margin_sar - (costed_revenue_sar - cost_sar)
) > 0.01