WITH source AS (
    SELECT * FROM {{ source('raw', 'CUSTOMERS_RAW') }}
),

deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY CUSTOMER_ID
            ORDER BY CREATED_AT DESC
        ) AS row_num
    FROM source
),

cleaned AS (
    SELECT
        CUSTOMER_ID,
        CASE
            WHEN CUSTOMER_NAME IS NULL OR TRIM(CUSTOMER_NAME) = '' THEN 'Unknown'
            ELSE TRIM(CUSTOMER_NAME)
        END AS CUSTOMER_NAME,
        CASE
            WHEN EMAIL IS NULL OR TRIM(EMAIL) = '' THEN NULL
            ELSE LOWER(TRIM(EMAIL))
        END AS EMAIL,
        CASE
            WHEN PHONE IS NULL OR TRIM(PHONE) = '' THEN NULL
            ELSE TRIM(PHONE)
        END AS PHONE,
        CASE
            WHEN ADDRESS IS NULL OR TRIM(ADDRESS) = '' THEN NULL
            ELSE TRIM(ADDRESS)
        END AS ADDRESS,
        TRIM(CITY) AS CITY,
        TRIM(STATE) AS STATE,
        TRY_TO_DATE(SIGNUP_DATE) AS SIGNUP_DATE,
        COALESCE(CUSTOMER_TIER, 'Unknown') AS CUSTOMER_TIER,
        TRY_TO_TIMESTAMP(CREATED_AT) AS CREATED_AT,
        TRY_TO_TIMESTAMP(UPDATED_AT) AS UPDATED_AT
    FROM deduplicated
    WHERE row_num = 1
)

SELECT * FROM cleaned
