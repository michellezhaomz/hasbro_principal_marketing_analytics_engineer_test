-- dim_product
-- Canonical product dimension. One row per product_id.
-- Source: stg_products (already deduplicated).
-- Includes all products including P9999 (Omega Mystery Pack) and P4040 placeholder.

with products as (
    select * from {{ ref('stg_products') }}
)

select
    product_id,
    sku,
    product_name,
    category,
    franchise,
    product_status,
    launch_date,
    age_grade,
    dq_invalid_launch_date,
    dq_was_duplicate
from products
