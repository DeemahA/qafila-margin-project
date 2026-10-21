-- Get valid supplier prices only
WITH valid_prices AS (
    SELECT
        p.sku,
        p.valid_from,
        ROUND(p.unit_cost_sar, 2) AS unit_cost_sar,
        p.source_file
    FROM {{ ref('stg_supplier_prices') }} p
    LEFT JOIN {{ ref('price_quarantine') }} q
        ON p.source_file = q.source_file
        AND p.sku = q.sku
        AND p.valid_from = q.valid_from
        AND p.raw_cost IS NOT DISTINCT FROM q.raw_cost
    WHERE q.reason IS NULL
),

-- Keep the latest file when the same SKU and date appear more than once
latest_prices AS (
    SELECT
        sku,
        valid_from,
        unit_cost_sar
    FROM valid_prices
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY sku, valid_from
        ORDER BY source_file DESC
    ) = 1
),

-- Compare each price with the previous one
price_changes AS (
    SELECT
        *,
        LAG(unit_cost_sar) OVER (
            PARTITION BY sku
            ORDER BY valid_from
        ) AS previous_cost
    FROM latest_prices
),

-- Keep a new version only when the cost changes
changed_prices AS (
    SELECT
        sku,
        valid_from,
        unit_cost_sar
    FROM price_changes
    WHERE previous_cost IS NULL
       OR unit_cost_sar <> previous_cost
)

-- Build the SCD Type 2 history
SELECT
    sku,
    unit_cost_sar,
    valid_from,
    LEAD(valid_from) OVER (
        PARTITION BY sku
        ORDER BY valid_from
    ) AS valid_to,
    LEAD(valid_from) OVER (
        PARTITION BY sku
        ORDER BY valid_from
    ) IS NULL AS is_current
FROM changed_prices