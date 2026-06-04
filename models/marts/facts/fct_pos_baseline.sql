-- fct_pos_baseline
-- POS baseline fact. One row per (retailer_id, product_id, baseline_method).
-- All available baseline methods are preserved — the model does not collapse to one.
-- The preferred method for lift calculations is controlled by var('default_baseline_method').
-- Consumers of this model should filter to their chosen method explicitly.

with baseline as (
    select * from {{ ref('stg_pos_baseline') }}
),

resolution as (
    select * from {{ ref('int_product_key_resolution') }}
),

final as (
    select
        b.baseline_id,
        UPPER(b.retailer_id)                                        as retailer_id,

        -- Resolved product_id
        r.resolved_product_id                                       as product_id,
        b.product_key                                               as product_key_raw,
        r.resolution_method                                         as product_key_resolution_method,
        r.is_resolvable                                             as product_key_is_resolvable,

        b.baseline_period_start,
        b.baseline_period_end,
        b.avg_weekly_units,
        b.avg_weekly_sales,
        b.baseline_method,
        b.seasonality_index,

        -- Flag whether this is the preferred baseline method per dbt var
        case
            when b.baseline_method = '{{ var("default_baseline_method") }}' then 1
            else 0
        end                                                         as is_preferred_method,

        b.dq_null_avg_units,
        b.dq_duplicate_baseline,
        b.has_multiple_baseline_methods,
        b.dq_product_key_is_sku

    from baseline b
    left join resolution r
        on b.product_key = r.raw_key
)

select * from final
