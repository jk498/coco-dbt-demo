
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select TOTAL_AMOUNT
from COCO_DBT_DEMO.ANALYTICS.stg_orders
where TOTAL_AMOUNT is null



  
  
      
    ) dbt_internal_test