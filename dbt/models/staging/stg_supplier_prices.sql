WITH source_data AS (
    SELECT
        filename,
        TRIM(sku) AS sku,
        TRY_CAST(valid_from AS DATE) AS valid_from,
        unit_cost AS raw_cost
    FROM {{ source('raw', 'supplier_prices') }}
),

cleaned AS (
    SELECT
        regexp_replace(
            translate(
                TRIM(raw_cost),
                '٠١٢٣٤٥٦٧٨٩٫',
                '0123456789.'
            ),
            ',',
            '.',
            'g'
        ) AS cleaned_cost,
        *
    FROM source_data
)

SELECT
    regexp_extract(filename, '[^/\\]+$') AS source_file,
    sku,
    valid_from,
    raw_cost,
    TRY_CAST(cleaned_cost AS DOUBLE) AS unit_cost_sar
FROM cleaned