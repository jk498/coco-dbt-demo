
    
    

with all_values as (

    select
        ORDER_STATUS as value_field,
        count(*) as n_records

    from COCO_DBT_DEMO.ANALYTICS.stg_orders
    group by ORDER_STATUS

)

select *
from all_values
where value_field not in (
    'delivered','shipped','pending','cancelled','returned'
)


