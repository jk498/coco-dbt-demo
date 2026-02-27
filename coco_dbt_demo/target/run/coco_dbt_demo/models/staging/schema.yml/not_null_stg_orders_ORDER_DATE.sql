
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select ORDER_DATE
from COCO_DBT_DEMO.ANALYTICS.stg_orders
where ORDER_DATE is null



  
  
      
    ) dbt_internal_test