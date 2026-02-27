
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

select
    CUSTOMER_ID as unique_field,
    count(*) as n_records

from COCO_DBT_DEMO.ANALYTICS.fct_customer_orders
where CUSTOMER_ID is not null
group by CUSTOMER_ID
having count(*) > 1



  
  
      
    ) dbt_internal_test