SELECT
    order_id,
    line_no,
    product_id,
    quantity,
    unit_price,
    discount,
    ROUND(
        quantity * unit_price - COALESCE(discount, 0),
        2
    ) AS line_revenue_sar

FROM {{ source('raw', 'order_items') }}