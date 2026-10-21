SELECT
    product_id,
    TRIM(sku) AS sku,
    name_en,
    name_ar,
    category,
    brand,
    unit_price,
    is_active

FROM {{ source('raw', 'products') }}