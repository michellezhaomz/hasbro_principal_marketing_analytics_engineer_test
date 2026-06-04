-- rpt_marketing_effectiveness
-- Unified marketing effectiveness view connecting:
--   campaigns, products, retailers, marketing spend, funnel activity, POS performance, and lift.
--
-- Grain: one row per (campaign_id, product_id, retailer_id, week_start_date).
-- Marketing metrics are aggregated from daily to weekly to match the POS grain.
-- Funnel metrics are aggregated by canonical stage for the same week.
--
-- This is the primary model for answering:
--   "For this campaign, on this product, at this retailer, in this week —
--    what did we spend, what did the funnel look like, how did POS move,
--    and what was the incremental lift?"
--
-- Attribution window note: spend and conversion metrics use the standard attribution
-- window (var('standard_attribution_window')) to avoid double-counting.
-- Full performance data by window is available in fct_marketing_performance.

with lift as (
    select * from {{ ref('fct_marketing_lift') }}
),

campaigns as (
    select * from {{ ref('dim_campaign') }}
),

products as (
    select * from {{ ref('dim_product') }}
),

retailers as (
    select * from {{ ref('dim_retailer') }}
),

-- Aggregate daily marketing performance to weekly
-- Filter to standard attribution window only
weekly_spend as (
    select
        campaign_id,
        -- Align activity_date to week_start
        date(activity_date, 'weekday 1', '-7 days')                as week_start_date,
        sum(spend)                                                  as weekly_spend,
        sum(impressions)                                            as weekly_impressions,
        sum(clicks)                                                 as weekly_clicks,
        sum(conversions)                                            as weekly_conversions,
        sum(revenue_attributed)                                     as weekly_revenue_attributed
    from {{ ref('fct_marketing_performance') }}
    where is_standard_attribution_window = 1
      and dq_null_spend = 0
    group by 1, 2
),

-- Aggregate funnel events to weekly by canonical stage
weekly_funnel as (
    select
        campaign_id,
        date(event_date, 'weekday 1', '-7 days')                   as week_start_date,
        sum(case when canonical_stage = 'awareness'
                  and canonical_event_type = 'impression'
             then event_count else 0 end)                           as weekly_awareness_impressions,
        sum(case when canonical_stage = 'consideration'
             then event_count else 0 end)                           as weekly_consideration_events,
        sum(case when canonical_stage = 'conversion'
             then event_count else 0 end)                           as weekly_conversion_events
    from {{ ref('fct_funnel_performance') }}
    where dq_null_event_count = 0
    group by 1, 2
),

final as (
    select
        -- Keys
        l.campaign_id,
        l.product_id,
        l.retailer_id,
        l.week_start_date,

        -- Campaign context
        c.campaign_name,
        c.platform,
        c.funnel_stage,
        c.campaign_type,
        l.campaign_start_date,
        l.campaign_end_date,

        -- Product context
        p.product_name,
        p.category,
        p.franchise,
        p.product_status,

        -- Retailer context
        r.retailer_name,
        r.channel,
        r.retailer_tier,
        r.dq_potential_duplicate_retailer,

        -- Marketing spend (weekly, standard attribution window)
        ws.weekly_spend,
        ws.weekly_impressions,
        ws.weekly_clicks,
        ws.weekly_conversions,
        ws.weekly_revenue_attributed,

        -- Derived marketing efficiency
        case
            when ws.weekly_impressions > 0 and ws.weekly_spend is not null
            then round(ws.weekly_spend / ws.weekly_impressions * 1000.0, 2)
            else null
        end                                                         as weekly_cpm,
        case
            when ws.weekly_spend > 0 and ws.weekly_revenue_attributed is not null
            then round(ws.weekly_revenue_attributed / ws.weekly_spend, 2)
            else null
        end                                                         as weekly_roas,

        -- Funnel shape
        wf.weekly_awareness_impressions,
        wf.weekly_consideration_events,
        wf.weekly_conversion_events,

        -- POS actuals
        l.actual_units,
        l.actual_sales,

        -- Baseline and expected
        l.expected_units,
        l.expected_sales,
        l.baseline_method,

        -- Lift
        l.absolute_unit_lift,
        l.pct_unit_lift,
        l.absolute_sales_lift,
        l.pct_sales_lift,

        -- Confound context
        l.is_confirmed_promo_week,
        l.is_oos,
        l.is_low_stock,
        l.promo_type,
        l.expected_discount_pct,

        -- Confidence
        l.lift_confidence,

        -- DQ flags
        l.dq_baseline_missing,
        l.dq_orphaned_retailer_id,
        l.dq_orphaned_product_key

    from lift l
    left join campaigns c
        on l.campaign_id = c.campaign_id
       and l.week_start_date >= c.start_date
       and l.week_start_date <= c.end_date
    left join products p
        on l.product_id = p.product_id
    left join retailers r
        on l.retailer_id = r.retailer_id
    left join weekly_spend ws
        on l.campaign_id = ws.campaign_id
       and l.week_start_date = ws.week_start_date
    left join weekly_funnel wf
        on l.campaign_id = wf.campaign_id
       and l.week_start_date = wf.week_start_date
)

select * from final
