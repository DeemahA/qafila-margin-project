SELECT
    store_id,
    city,
    name_en,
    name_ar,
    lat,
    lon,
    opened_at

FROM {{ source('raw', 'stores') }}