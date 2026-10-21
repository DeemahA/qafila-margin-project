-- Get the supplier prices from staging
WITH prices AS (
    SELECT *
    FROM {{ ref('stg_supplier_prices') }}
),

-- Check if the SKU exists and if the cost is valid
checked AS (
    SELECT
        p.source_file,
        p.sku,
        p.valid_from,
        p.raw_cost,
        CASE
            -- SKU not found in our products
            WHEN pr.product_id IS NULL
                THEN 'unknown_sku'

            -- Cost is missing, zero, or negative
            WHEN p.unit_cost_sar IS NULL
                 OR p.unit_cost_sar <= 0
                THEN 'invalid_cost'

            ELSE NULL
        END AS reason
    FROM prices p
    LEFT JOIN {{ ref('stg_products') }} pr
        ON p.sku = pr.sku
)

-- Keep only the rows with data issues
SELECT
    source_file,
    sku,
    valid_from,
    raw_cost,
    reason
FROM checked
WHERE reason IS NOT NULL