-- int_funnel_event_mapping
-- Maps platform-specific raw event names to canonical funnel stages and event types.
-- SQLite does not support VALUES() as a table constructor so we use UNION ALL instead.
-- AI-suggested mapping note:
--   TikTok complete_payment -> purchase is AI002 (confidence 0.87, UNREVIEWED)

with event_map as (
    select 'Meta' as platform, 'impression' as raw_event_name, 'awareness' as canonical_stage, 'impression' as canonical_event_type, 0 as requires_human_review union all
    select 'Meta', 'impressions', 'awareness', 'impression', 0 union all
    select 'Meta', 'link_click', 'consideration', 'click', 0 union all
    select 'Meta', 'landing_page_view', 'consideration', 'page_view', 0 union all
    select 'Meta', 'purchase', 'conversion', 'purchase', 0 union all
    select 'Instagram', 'impression', 'awareness', 'impression', 0 union all
    select 'Instagram', 'impressions', 'awareness', 'impression', 0 union all
    select 'Instagram', 'link_click', 'consideration', 'click', 0 union all
    select 'Instagram', 'landing_page_view', 'consideration', 'page_view', 0 union all
    select 'Instagram', 'purchase', 'conversion', 'purchase', 0 union all
    select 'Google', 'impressions', 'awareness', 'impression', 0 union all
    select 'Google', 'impression', 'awareness', 'impression', 0 union all
    select 'Google', 'click', 'consideration', 'click', 0 union all
    select 'Google', 'conversion', 'conversion', 'purchase', 0 union all
    select 'YouTube', 'views', 'awareness', 'video_view', 0 union all
    select 'YouTube', 'impressions', 'awareness', 'impression', 0 union all
    select 'YouTube', 'impression', 'awareness', 'impression', 0 union all
    select 'YouTube', 'engaged_view', 'consideration', 'engaged_view', 0 union all
    select 'YouTube', 'conversion', 'conversion', 'purchase', 0 union all
    select 'TikTok', 'impression', 'awareness', 'impression', 0 union all
    select 'TikTok', 'impressions', 'awareness', 'impression', 0 union all
    select 'TikTok', 'video_view', 'awareness', 'video_view', 0 union all
    select 'TikTok', 'click', 'consideration', 'click', 0 union all
    -- AI002: complete_payment -> purchase (0.87 confidence, UNREVIEWED - requires human sign-off)
    select 'TikTok', 'complete_payment', 'conversion', 'purchase', 1
),

funnel_events as (
    select * from {{ ref('stg_funnel_events') }}
),

final as (
    select
        fe.event_id,
        fe.campaign_id,
        fe.platform,
        fe.platform_raw,
        fe.event_date,
        fe.raw_event_name,
        fe.raw_event_name_original,
        fe.event_count,

        em.canonical_stage,
        em.canonical_event_type,

        case when em.canonical_stage is null then 1 else 0 end      as dq_unmapped_event,
        coalesce(em.requires_human_review, 0)                       as requires_human_review,

        fe.dq_null_event_count,
        fe.platform_definition_note

    from funnel_events fe
    left join event_map em
        on fe.platform = em.platform
       and fe.raw_event_name = em.raw_event_name
)

select * from final
