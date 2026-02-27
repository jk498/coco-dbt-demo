
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select TOTAL_ORDERS
from COCO_DBT_DEMO.ANALYTICS.fct_customer_orders
where TOTAL_ORDERS is null



  
  
      
    ) dbt_internal_test