
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        CUSTOMER_TIER as value_field,
        count(*) as n_records

    from COCO_DBT_DEMO.ANALYTICS.stg_customers
    group by CUSTOMER_TIER

)

select *
from all_values
where value_field not in (
    'Gold','Silver','Bronze','Platinum','Unknown'
)



  
  
      
    ) dbt_internal_test