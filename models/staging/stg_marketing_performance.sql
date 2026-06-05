-- stg_marketing_performance
-- Normalizes daily marketing performance data.
-- Key issues handled:
--   - spend 'N/A' string -> NULL with flag
--   - currency variants (US Dollars, usd) -> USD
--   - attribution_window variants (7-day click -> 7d_click) -> normalized
--   - Duplicate performance_id rows: detected systematically via ROW_NUMBER(),
--     flagged with dq_duplicate_record = 1, only first occurrence retained
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

deduped as (
    select
        *,
        case
            when count(*) over (partition by performance_id) > 1 then 1
            else 0
        end as dq_duplicate_record,

        case
            when spend = 'N/A' or spend is null or trim(spend) = '' then 1
            else 0
        end as dq_null_spend,

        row_number() over (
            partition by performance_id
            order by rowid
        ) as row_num

    from raw
),

final as (
    select
        performance_id,
        campaign_id,

        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'platform' and l.raw_value = f.platform limit 1),
            f.platform
        )                                                           as platform,
        f.platform                                                  as platform_raw,

        activity_date,

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

        case
            when link_clicks is null or trim(link_clicks) = '' then null
            else cast(link_clicks as integer)
        end                                                         as link_clicks,

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

        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'attribution_window' and l.raw_value = f.attribution_window limit 1),
            f.attribution_window
        )                                                           as attribution_window,
        f.attribution_window                                        as attribution_window_raw,

        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'currency' and l.raw_value = f.currency limit 1),
            f.currency
        )                                                           as currency,

        dq_duplicate_record,
        dq_null_spend

    from deduped f
    where row_num = 1
)

select * from final