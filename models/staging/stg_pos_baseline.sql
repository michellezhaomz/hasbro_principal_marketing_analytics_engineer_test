-- stg_pos_baseline
-- Normalizes POS baseline history.
-- Key issues handled:
--   - avg_weekly_units 'unknown' string -> NULL with flag
--   - retailer_id: normalized to UPPER
--   - product_key: SKU-based keys flagged (resolved in int_product_key_resolution)
--   - Duplicate baseline_id BLDUP: both rows flagged, neither auto-resolved
--     Default: prior_8_weeks method preferred (set in dbt_project.yml vars)
--   - Mixed baseline methods per retailer/product: surfaced, not collapsed

with raw as (
    select * from {{ source('main', 'pos_baseline_history_raw') }}
),

final as (
    select
        baseline_id,
        UPPER(retailer_id)                                          as retailer_id,

        product_key,

        -- Flag SKU-based product keys
        case
            when upper(product_key) like 'SKU-%' then 1
            else 0
        end                                                         as dq_product_key_is_sku,

        baseline_period_start,
        baseline_period_end,

        -- Cast avg_weekly_units: 'unknown' -> NULL
        case
            when avg_weekly_units = 'unknown'
              or avg_weekly_units is null
              or trim(cast(avg_weekly_units as text)) = '' then null
            else cast(avg_weekly_units as real)
        end                                                         as avg_weekly_units,

        case
            when avg_weekly_units = 'unknown' 
            or avg_weekly_units is null
            or trim(cast(avg_weekly_units as text)) = '' then 1
            else 0
        end                                                         as dq_null_avg_units,

        case
            when avg_weekly_sales is null
            or trim(cast(avg_weekly_sales as text)) = '' then null
            else cast(avg_weekly_sales as real)
        end                                                         as avg_weekly_sales,

        case
            when avg_weekly_sales is null
            or trim(cast(avg_weekly_sales as text)) = '' then 1
            else 0
        end                                                         as dq_null_avg_sales, 

        baseline_method,

        case
            when cast(seasonality_index as real) is null then 1.0
            else cast(seasonality_index as real)
        end                                                         as seasonality_index,

        -- Flag duplicate baseline_id
        case
            when count(*) over (partition by retailer_id, product_key, baseline_method) > 1 then 1
            else 0
        end                                                         as dq_duplicate_baseline,

        -- Flag records where same retailer/product has multiple baseline methods
        -- SQLite does not support COUNT(DISTINCT) in window functions; using correlated subquery
        case
            when (
                select count(distinct b2.baseline_method)
                from pos_baseline_history_raw b2
                where UPPER(b2.retailer_id) = UPPER(raw.retailer_id)
                  and b2.product_key = raw.product_key
            ) > 1 then 1
            else 0
        end                                                         as has_multiple_baseline_methods

    from raw
)

select * from final
