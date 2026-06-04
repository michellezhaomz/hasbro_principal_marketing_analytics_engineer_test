-- mart_data_quality_summary
-- Queryable summary of all data quality flags across staging models.
-- One row per (source_table, dq_flag, count_flagged).
-- Allows analysts and engineers to monitor data quality at a glance
-- and track whether issues are growing or resolving over time.

with dq_products as (
    select 'stg_products' as source_table, 'dq_invalid_launch_date' as dq_flag, count(*) as count_flagged
    from {{ ref('stg_products') }} where dq_invalid_launch_date = 1
    union all
    select 'stg_products', 'dq_was_duplicate', count(*)
    from {{ ref('stg_products') }} where dq_was_duplicate = 1
),

dq_retailers as (
    select 'stg_retailers', 'dq_potential_duplicate_retailer', count(*)
    from {{ ref('stg_retailers') }} where dq_potential_duplicate_retailer = 1
),

dq_campaigns as (
    select 'stg_campaigns', 'dq_product_key_is_sku', count(*)
    from {{ ref('stg_campaigns') }} where dq_product_key_is_sku = 1
    union all
    select 'stg_campaigns', 'dq_orphaned_product_key', count(*)
    from {{ ref('stg_campaigns') }} where dq_orphaned_product_key = 1
),

dq_performance as (
    select 'stg_marketing_performance', 'dq_null_spend', count(*)
    from {{ ref('stg_marketing_performance') }} where dq_null_spend = 1
),

dq_funnel as (
    select 'stg_funnel_events', 'dq_null_event_count', count(*)
    from {{ ref('stg_funnel_events') }} where dq_null_event_count = 1
),

dq_pos as (
    select 'stg_pos_weekly', 'is_return_adjustment', count(*)
    from {{ ref('stg_pos_weekly') }} where is_return_adjustment = 1
    union all
    select 'stg_pos_weekly', 'dq_product_key_is_sku', count(*)
    from {{ ref('stg_pos_weekly') }} where dq_product_key_is_sku = 1
    union all
    select 'stg_pos_weekly', 'dq_orphaned_product_key', count(*)
    from {{ ref('stg_pos_weekly') }} where dq_orphaned_product_key = 1
    union all
    select 'stg_pos_weekly', 'dq_orphaned_retailer_id', count(*)
    from {{ ref('stg_pos_weekly') }} where dq_orphaned_retailer_id = 1
    union all
    select 'stg_pos_weekly', 'dq_units_sales_sign_mismatch', count(*)
    from {{ ref('stg_pos_weekly') }} where dq_units_sales_sign_mismatch = 1
    union all
    select 'stg_pos_weekly', 'dq_duplicate_grain', count(*)
    from {{ ref('stg_pos_weekly') }} where dq_duplicate_grain = 1
),

dq_baseline as (
    select 'stg_pos_baseline', 'dq_null_avg_units', count(*)
    from {{ ref('stg_pos_baseline') }} where dq_null_avg_units = 1
    union all
    select 'stg_pos_baseline', 'dq_duplicate_baseline', count(*)
    from {{ ref('stg_pos_baseline') }} where dq_duplicate_baseline = 1
    union all
    select 'stg_pos_baseline', 'has_multiple_baseline_methods', count(*)
    from {{ ref('stg_pos_baseline') }} where has_multiple_baseline_methods = 1
    union all
    select 'stg_pos_baseline', 'dq_product_key_is_sku', count(*)
    from {{ ref('stg_pos_baseline') }} where dq_product_key_is_sku = 1
),

dq_promo as (
    select 'stg_promo_calendar', 'dq_orphaned_retailer_id', count(*)
    from {{ ref('stg_promo_calendar') }} where dq_orphaned_retailer_id = 1
    union all
    select 'stg_promo_calendar', 'dq_null_discount_pct', count(*)
    from {{ ref('stg_promo_calendar') }} where dq_null_discount_pct = 1
),

dq_ai as (
    select 'stg_ai_taxonomy_suggestions', 'is_pending_review', count(*)
    from {{ ref('stg_ai_taxonomy_suggestions') }} where is_pending_review = 1
),

dq_lift as (
    select 'fct_marketing_lift', 'lift_confidence_clean', count(*)
    from {{ ref('fct_marketing_lift') }} where lift_confidence = 'clean'
    union all
    select 'fct_marketing_lift', 'lift_confidence_confounded', count(*)
    from {{ ref('fct_marketing_lift') }} where lift_confidence = 'confounded'
    union all
    select 'fct_marketing_lift', 'lift_confidence_incomplete', count(*)
    from {{ ref('fct_marketing_lift') }} where lift_confidence = 'incomplete'
    union all
    select 'fct_marketing_lift', 'lift_confidence_unresolvable', count(*)
    from {{ ref('fct_marketing_lift') }} where lift_confidence = 'unresolvable'
),

all_flags as (
    select * from dq_products
    union all select * from dq_retailers
    union all select * from dq_campaigns
    union all select * from dq_performance
    union all select * from dq_funnel
    union all select * from dq_pos
    union all select * from dq_baseline
    union all select * from dq_promo
    union all select * from dq_ai
    union all select * from dq_lift
)

select
    source_table,
    dq_flag,
    count_flagged
from all_flags
where count_flagged > 0
order by source_table, dq_flag
