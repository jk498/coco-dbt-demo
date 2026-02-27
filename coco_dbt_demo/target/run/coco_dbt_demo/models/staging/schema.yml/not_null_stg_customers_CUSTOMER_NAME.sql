
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select CUSTOMER_NAME
from COCO_DBT_DEMO.ANALYTICS.stg_customers
where CUSTOMER_NAME is null



  
  
      
    ) dbt_internal_test