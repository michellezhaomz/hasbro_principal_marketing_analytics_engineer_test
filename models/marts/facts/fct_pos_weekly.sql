-- fct_pos_weekly
-- Weekly POS performance fact. One row per (retailer_id, product_id, week_start_date).
-- Grain: clean records only — returns/adjustments are included but flagged,
-- allowing downstream models to exclude or include them as needed.
-- product_key is resolved to canonical product_id via int_product_key_resolution.

with pos as (
    select * from {{ ref('stg_pos_weekly') }}
),

resolution as (
    select * from {{ ref('int_product_key_resolution') }}
),

promos as (
    select
        UPPER(retailer_id)  as retailer_id,
        product_key,
        promo_start_date,
        promo_end_date,
        promo_type,
        expected_discount_pct,
        funding_source,
        dq_orphaned_retailer_id
    from {{ ref('stg_promo_calendar') }}
),

final as (
    select
        p.pos_id,
        p.retailer_id,

        -- Resolved product_id
        r.resolved_product_id                                       as product_id,
        p.product_key                                               as product_key_raw,
        r.resolution_method                                         as product_key_resolution_method,
        r.is_resolvable                                             as product_key_is_resolvable,

        p.week_start_date,

        p.units_sold,
        p.gross_sales,
        p.inventory_units,
        p.regular_price,
        p.promo_price,
        p.is_promo_week,
        p.on_hand_status,
        p.is_oos,
        p.is_low_stock,
        p.is_return_adjustment,
        p.region,
        p.country,

        -- Join to promo calendar for additional promotion context
        pc.promo_type,
        pc.expected_discount_pct,
        pc.funding_source,

        -- Combined promo flag: POS-reported OR calendar-confirmed
        case
            when p.is_promo_week = 1
              or (
                  pc.promo_start_date is not null
                  and p.week_start_date >= pc.promo_start_date
                  and p.week_start_date <= pc.promo_end_date
              ) then 1
            else 0
        end                                                         as is_confirmed_promo_week,

        -- DQ flags
        p.dq_product_key_is_sku,
        p.dq_orphaned_product_key,
        p.dq_orphaned_retailer_id,
        p.dq_units_sales_sign_mismatch,
        p.dq_duplicate_grain

    from pos p
    left join resolution r
        on p.product_key = r.raw_key

    -- Join promo calendar: match on retailer, product, and week overlap
    left join promos pc
        on p.retailer_id = pc.retailer_id
       and p.product_key = pc.product_key
       and p.week_start_date >= pc.promo_start_date
       and p.week_start_date <= pc.promo_end_date
       and pc.dq_orphaned_retailer_id = 0
)

select * from final
