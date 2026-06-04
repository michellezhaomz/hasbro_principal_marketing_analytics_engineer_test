-- fct_marketing_lift
-- Marketing lift fact. One row per (campaign_id, product_id, retailer_id, week_start_date).
-- Compares actual POS performance during campaign exposure windows to expected baseline.
--
-- Lift calculation methodology:
--   expected_units = avg_weekly_units * seasonality_index
--   absolute_unit_lift = actual_units - expected_units
--   pct_unit_lift = absolute_unit_lift / expected_units
--
-- Baseline selection:
--   Uses var('default_baseline_method') preference. If preferred method unavailable,
--   falls back to any available non-duplicate baseline for that retailer/product.
--
-- Campaign window definition:
--   Weeks where week_start_date falls within campaign start_date and end_date.
--
-- Lift confidence classification:
--   clean       - No active promo, not OOS, baseline exists, no DQ flags
--   confounded  - Active promo OR OOS during measurement week
--   incomplete  - Baseline missing or has DQ issues
--   unresolvable - Product key unresolvable or retailer orphaned
--
-- Confound flags allow analysts to report clean lift separately from all-week lift.

with campaigns as (
    select
        campaign_id,
        product_id,
        start_date,
        end_date,
        platform,
        funnel_stage,
        campaign_type,
        product_key_is_resolvable
    from {{ ref('dim_campaign') }}
),

pos as (
    select *
    from {{ ref('fct_pos_weekly') }}
    -- Exclude return/adjustment transactions from lift numerator
    where is_return_adjustment = 0
),

-- Select baseline: prefer default_baseline_method, fall back to any clean baseline
baseline_ranked as (
    select
        *,
        row_number() over (
            partition by retailer_id, product_id
            order by
                is_preferred_method desc,
                dq_duplicate_baseline asc,
                dq_null_avg_units asc
        ) as baseline_rank
    from {{ ref('fct_pos_baseline') }}
    where product_key_is_resolvable = 1
      and dq_duplicate_baseline = 0
),

baseline as (
    select * from baseline_ranked where baseline_rank = 1
),

-- Build campaign-week-retailer spine
-- For each campaign, find all POS weeks within the campaign exposure window
campaign_pos_weeks as (
    select
        c.campaign_id,
        c.product_id,
        c.start_date                                                as campaign_start_date,
        c.end_date                                                  as campaign_end_date,
        c.platform,
        c.funnel_stage,
        c.campaign_type,
        c.product_key_is_resolvable,
        p.retailer_id,
        p.week_start_date,
        p.units_sold                                                as actual_units,
        p.gross_sales                                               as actual_sales,
        p.is_confirmed_promo_week,
        p.is_oos,
        p.is_low_stock,
        p.on_hand_status,
        p.promo_type,
        p.expected_discount_pct,
        p.dq_orphaned_retailer_id,
        p.dq_orphaned_product_key

    from campaigns c
    inner join pos p
        on c.product_id = p.product_id
       and p.week_start_date >= c.start_date
       and p.week_start_date <= c.end_date
    where c.product_key_is_resolvable = 1
),

-- Join baseline to campaign-pos-weeks
with_baseline as (
    select
        cpw.*,

        b.avg_weekly_units,
        b.avg_weekly_sales,
        b.baseline_method,
        b.seasonality_index,
        b.dq_null_avg_units,
        b.dq_multiple_baseline_methods,

        -- Expected values: adjust baseline by seasonality
        case
            when b.avg_weekly_units is not null and b.seasonality_index is not null
            then round(b.avg_weekly_units * b.seasonality_index, 2)
            else null
        end                                                         as expected_units,

        case
            when b.avg_weekly_sales is not null and b.seasonality_index is not null
            then round(b.avg_weekly_sales * b.seasonality_index, 2)
            else null
        end                                                         as expected_sales,

        -- Flag missing baseline
        case when b.retailer_id is null then 1 else 0 end          as dq_baseline_missing

    from campaign_pos_weeks cpw
    left join baseline b
        on cpw.retailer_id = b.retailer_id
       and cpw.product_id = b.product_id
),

final as (
    select
        campaign_id,
        product_id,
        retailer_id,
        week_start_date,
        campaign_start_date,
        campaign_end_date,
        platform,
        funnel_stage,
        campaign_type,

        -- Actuals
        actual_units,
        actual_sales,

        -- Expected (baseline * seasonality)
        expected_units,
        expected_sales,
        baseline_method,
        seasonality_index,

        -- Lift calculations (NULL-safe)
        case
            when actual_units is not null and expected_units is not null
            then round(actual_units - expected_units, 2)
            else null
        end                                                         as absolute_unit_lift,

        case
            when actual_units is not null and expected_units is not null and expected_units > 0
            then round((actual_units - expected_units) / expected_units, 4)
            else null
        end                                                         as pct_unit_lift,

        case
            when actual_sales is not null and expected_sales is not null
            then round(actual_sales - expected_sales, 2)
            else null
        end                                                         as absolute_sales_lift,

        case
            when actual_sales is not null and expected_sales is not null and expected_sales > 0
            then round((actual_sales - expected_sales) / expected_sales, 4)
            else null
        end                                                         as pct_sales_lift,

        -- Confound flags
        is_confirmed_promo_week,
        is_oos,
        is_low_stock,
        promo_type,
        expected_discount_pct,

        -- Lift confidence classification
        case
            when dq_orphaned_retailer_id = 1
              or dq_orphaned_product_key = 1
              or product_key_is_resolvable = 0 then 'unresolvable'
            when dq_baseline_missing = 1
              or dq_null_avg_units = 1         then 'incomplete'
            when is_confirmed_promo_week = 1
              or is_oos = 1                    then 'confounded'
            else                                    'clean'
        end                                                         as lift_confidence,

        -- DQ flags
        dq_baseline_missing,
        dq_null_avg_units,
        dq_multiple_baseline_methods,
        dq_orphaned_retailer_id,
        dq_orphaned_product_key

    from with_baseline
)

select * from final
