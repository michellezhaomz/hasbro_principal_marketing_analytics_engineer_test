-- dim_retailer
-- Canonical retailer dimension. One row per retailer_id.
-- R001/R006 near-duplicate is preserved with is_potential_duplicate flag.
-- Do NOT merge until business confirmation. See docs/DATA_QUALITY_FINDINGS.md R-1.

with retailers as (
    select * from {{ ref('stg_retailers') }}
)

select
    retailer_id,
    retailer_name,
    channel,
    region,
    country,
    retailer_tier,
    dq_potential_duplicate_retailer
from retailers
