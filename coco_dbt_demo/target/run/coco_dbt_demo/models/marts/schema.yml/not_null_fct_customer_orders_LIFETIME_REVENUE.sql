
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select LIFETIME_REVENUE
from COCO_DBT_DEMO.ANALYTICS.fct_customer_orders
where LIFETIME_REVENUE is null



  
  
      
    ) dbt_internal_test