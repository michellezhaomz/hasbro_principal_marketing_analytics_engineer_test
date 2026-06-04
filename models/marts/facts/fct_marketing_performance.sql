-- fct_marketing_performance
-- Daily marketing performance fact. One row per (campaign_id, platform, activity_date, attribution_window).
--
-- IMPORTANT: attribution_window is kept as a dimension, not aggregated over.
-- Aggregating across different attribution windows (e.g. 1d_click + 7d_click) for
-- the same campaign double-counts conversions. Always filter to a single window
-- before calculating ROAS. The standard reporting window is defined in dbt_project.yml
-- vars.standard_attribution_window (default: 7d_click).
--
-- Derived efficiency metrics are pre-calculated here so BI tools don't need to
-- reimplement them. NULL-safe division applied throughout.

with perf as (
    select * from {{ ref('stg_marketing_performance') }}
),

campaigns as (
    select campaign_id, product_id, platform, funnel_stage, campaign_type
    from {{ ref('dim_campaign') }}
),

final as (
    select
        p.performance_id,
        p.campaign_id,
        c.product_id,
        p.platform,
        p.platform_raw,
        p.activity_date,
        p.attribution_window,
        p.attribution_window_raw,
        c.funnel_stage,
        c.campaign_type,

        -- Core metrics
        p.spend,
        p.impressions,
        p.reach,
        p.clicks,
        p.link_clicks,
        p.video_views,
        p.engagements,
        p.conversions,
        p.revenue_attributed,
        p.currency,

        -- Derived efficiency metrics (NULL-safe)
        case
            when p.impressions > 0 and p.spend is not null
            then round(p.spend / p.impressions * 1000.0, 4)
            else null
        end                                                         as cpm,

        case
            when p.clicks > 0 and p.spend is not null
            then round(p.spend / p.clicks, 4)
            else null
        end                                                         as cpc,

        case
            when p.impressions > 0
            then round(cast(p.clicks as real) / p.impressions, 6)
            else null
        end                                                         as ctr,

        case
            when p.clicks > 0
            then round(cast(p.conversions as real) / p.clicks, 6)
            else null
        end                                                         as cvr,

        case
            when p.spend is not null and p.spend > 0
            then round(p.revenue_attributed / p.spend, 4)
            else null
        end                                                         as roas,

        -- Flag whether this row matches the standard attribution window
        case
            when p.attribution_window = '{{ var("standard_attribution_window") }}' then 1
            else 0
        end                                                         as is_standard_attribution_window,

        p.dq_null_spend

    from perf p
    left join campaigns c on p.campaign_id = c.campaign_id
)

select * from final
