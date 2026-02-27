
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select CUSTOMER_TIER
from COCO_DBT_DEMO.ANALYTICS.fct_customer_orders
where CUSTOMER_TIER is null



  
  
      
    ) dbt_internal_test