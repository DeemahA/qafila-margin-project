-- Check for duplicate price versions for the same SKU and date
SELECT
    sku,
    valid_from,
    COUNT(*) AS duplicate_count
FROM {{ ref('product_cost_history') }}
GROUP BY sku, valid_from
HAVING COUNT(*) > 1