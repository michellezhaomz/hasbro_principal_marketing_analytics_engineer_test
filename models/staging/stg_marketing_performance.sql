-- stg_marketing_performance
-- Normalizes daily marketing performance data.
-- Key issues handled:
--   - spend 'N/A' string -> NULL with flag
--   - currency variants (US Dollars, usd) -> USD
--   - attribution_window variants (7-day click -> 7d_click) -> normalized
--   - Duplicate rows (MPDUP1): flagged and excluded from clean dataset
--   - platform normalized via taxonomy lookup
--   - Empty string metrics (link_clicks, video_views) -> NULL (platform-specific fields)

with raw as (
    select * from {{ source('main', 'marketing_performance_raw') }}
),

lookup as (
    select taxonomy_type, raw_value, canonical_value
    from {{ source('main', 'taxonomy_lookup_raw') }}
    union all
    select taxonomy_type, raw_value, canonical_value
    from {{ ref('taxonomy_supplement') }}
),

flagged as (
    select
        *,
        -- Flag duplicate performance_id
        case
            when performance_id = 'MPDUP1' then 1
            else 0
        end as dq_duplicate_record,

        -- Flag null spend
        case
            when spend = 'N/A' or spend is null or trim(spend) = '' then 1
            else 0
        end as dq_null_spend

    from raw
),

final as (
    select
        performance_id,
        campaign_id,

        -- Normalize platform
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'platform' and l.raw_value = f.platform limit 1),
            f.platform
        )                                                           as platform,
        f.platform                                                  as platform_raw,

        activity_date,

        -- Cast spend: N/A and blanks -> NULL
        case
            when spend = 'N/A' or trim(spend) = '' then null
            else cast(spend as real)
        end                                                         as spend,

        cast(impressions as integer)                                as impressions,

        case
            when reach is null or trim(reach) = '' then null
            else cast(reach as integer)
        end                                                         as reach,

        cast(clicks as integer)                                     as clicks,

        -- link_clicks: NULL when blank (platform-specific field, not applicable to all)
        case
            when link_clicks is null or trim(link_clicks) = '' then null
            else cast(link_clicks as integer)
        end                                                         as link_clicks,

        -- video_views: NULL when blank
        case
            when video_views is null or trim(video_views) = '' then null
            else cast(video_views as integer)
        end                                                         as video_views,

        case
            when engagements is null or trim(engagements) = '' then null
            else cast(engagements as integer)
        end                                                         as engagements,

        cast(conversions as integer)                                as conversions,
        cast(revenue_attributed as real)                            as revenue_attributed,

        -- Normalize attribution_window
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'attribution_window' and l.raw_value = f.attribution_window limit 1),
            f.attribution_window
        )                                                           as attribution_window,
        f.attribution_window                                        as attribution_window_raw,

        -- Normalize currency
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'currency' and l.raw_value = f.currency limit 1),
            f.currency
        )                                                           as currency,

        dq_duplicate_record,
        dq_null_spend

    from flagged f
    -- Exclude duplicate rows: MPDUP1 is an erroneous double-load
    -- The non-duplicate row MP00013 covers the same campaign/date/platform
    where dq_duplicate_record = 0
)

select * from final
