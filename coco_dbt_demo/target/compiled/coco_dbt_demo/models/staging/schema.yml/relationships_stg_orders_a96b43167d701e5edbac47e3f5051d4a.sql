
    
    

with child as (
    select CUSTOMER_ID as from_field
    from COCO_DBT_DEMO.ANALYTICS.stg_orders
    where CUSTOMER_ID is not null
),

parent as (
    select CUSTOMER_ID as to_field
    from COCO_DBT_DEMO.ANALYTICS.stg_customers
)

select
    from_field

from child
left join parent
    on child.from_field = parent.to_field

where parent.to_field is null


