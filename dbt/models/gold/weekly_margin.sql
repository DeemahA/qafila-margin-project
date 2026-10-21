-- Get delivered orders from the project start date
WITH delivered_orders AS (
    SELECT
        order_id,
        store_id,
        order_date,
        EXTRACT('week' FROM order_date)::INTEGER AS iso_week
    FROM {{ ref('stg_orders') }}
    WHERE LOWER(TRIM(status)) = 'delivered'
      AND order_date >= DATE '2026-08-31'
),

-- Get order lines with valid quantities
order_lines AS (
    SELECT
        o.order_id,
        o.order_date,
        o.iso_week,
        o.store_id,
        i.product_id,
        i.quantity,
        i.line_revenue_sar
    FROM delivered_orders o
    JOIN {{ ref('stg_order_items') }} i
        ON o.order_id = i.order_id
    WHERE i.quantity > 0
),

-- Add city, category, and the historical cost for each order date
lines_with_cost AS (
    SELECT
        l.*,
        s.city,
        p.category,
        h.unit_cost_sar,
        ROUND(l.quantity * h.unit_cost_sar, 2) AS line_cost_sar
    FROM order_lines l
    JOIN {{ ref('stg_stores') }} s
        ON l.store_id = s.store_id
    JOIN {{ ref('stg_products') }} p
        ON l.product_id = p.product_id
    LEFT JOIN {{ ref('product_cost_history') }} h
        ON p.sku = h.sku
       AND l.order_date >= h.valid_from
       AND (l.order_date < h.valid_to OR h.valid_to IS NULL)
)

-- Calculate weekly gross margin by city and category
SELECT
    iso_week,
    city,
    category,
    COUNT(*)::INTEGER AS lines,
    ROUND(SUM(line_revenue_sar), 2)::DOUBLE AS revenue_sar,
    ROUND(SUM(
        CASE WHEN unit_cost_sar IS NOT NULL
             THEN line_revenue_sar ELSE 0 END
    ), 2)::DOUBLE AS costed_revenue_sar,
    ROUND(SUM(COALESCE(line_cost_sar, 0)), 2)::DOUBLE AS cost_sar,
    ROUND(
        SUM(CASE WHEN unit_cost_sar IS NOT NULL
                 THEN line_revenue_sar ELSE 0 END)
        - SUM(COALESCE(line_cost_sar, 0)),
        2
    )::DOUBLE AS margin_sar,
    COUNT(*) FILTER (
        WHERE unit_cost_sar IS NULL
    )::INTEGER AS uncosted_lines
FROM lines_with_cost
GROUP BY iso_week, city, category