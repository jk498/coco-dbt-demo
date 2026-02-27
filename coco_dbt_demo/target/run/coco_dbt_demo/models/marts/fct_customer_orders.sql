
  
    

create or replace transient table COCO_DBT_DEMO.ANALYTICS.fct_customer_orders
    
    
    
    as (WITH customers AS (
    SELECT * FROM COCO_DBT_DEMO.ANALYTICS.stg_customers
),

orders AS (
    SELECT * FROM COCO_DBT_DEMO.ANALYTICS.stg_orders
),

customer_orders AS (
    SELECT
        c.CUSTOMER_ID,
        c.CUSTOMER_NAME,
        c.EMAIL,
        c.CITY,
        c.STATE,
        c.CUSTOMER_TIER,
        c.SIGNUP_DATE,
        COUNT(o.ORDER_ID) AS TOTAL_ORDERS,
        SUM(CASE WHEN o.ORDER_STATUS = 'delivered' THEN 1 ELSE 0 END) AS DELIVERED_ORDERS,
        SUM(CASE WHEN o.ORDER_STATUS = 'cancelled' THEN 1 ELSE 0 END) AS CANCELLED_ORDERS,
        SUM(CASE WHEN o.ORDER_STATUS = 'returned' THEN 1 ELSE 0 END) AS RETURNED_ORDERS,
        COALESCE(SUM(o.TOTAL_AMOUNT), 0) AS LIFETIME_REVENUE,
        COALESCE(AVG(o.TOTAL_AMOUNT), 0) AS AVG_ORDER_VALUE,
        MIN(o.ORDER_DATE) AS FIRST_ORDER_DATE,
        MAX(o.ORDER_DATE) AS LAST_ORDER_DATE,
        DATEDIFF('day', MIN(o.ORDER_DATE), MAX(o.ORDER_DATE)) AS CUSTOMER_TENURE_DAYS
    FROM customers c
    LEFT JOIN orders o ON c.CUSTOMER_ID = o.CUSTOMER_ID
    GROUP BY
        c.CUSTOMER_ID,
        c.CUSTOMER_NAME,
        c.EMAIL,
        c.CITY,
        c.STATE,
        c.CUSTOMER_TIER,
        c.SIGNUP_DATE
)

SELECT * FROM customer_orders
    )
;


  