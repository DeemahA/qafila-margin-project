-- Check that each SKU has exactly one current price
SELECT
    sku,
    COUNT(*) AS current_count
FROM {{ ref('product_cost_history') }}
GROUP BY sku
HAVING SUM(
    CASE WHEN is_current = TRUE THEN 1 ELSE 0 END
) <> 1