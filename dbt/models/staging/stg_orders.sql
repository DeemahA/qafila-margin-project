SELECT
    order_id,
    customer_id,
    store_id,
    status,
    payment_method,
    promo_code,
    delivery_fee,
    created_at,
    updated_at,

    CAST(
        CAST(created_at AS TIMESTAMP)
        + INTERVAL '3 hours'
        AS DATE
    ) AS order_date

FROM {{ source('raw', 'orders') }}