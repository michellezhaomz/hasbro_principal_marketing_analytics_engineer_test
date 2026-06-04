-- stg_funnel_events
-- Normalizes platform funnel event data.
-- Key issues handled:
--   - Platform normalization (Meta/Facebook -> Meta)
--   - raw_event_count 'unknown' -> NULL with flag
--   - raw_event_name: lowercased for consistent matching in int_funnel_event_mapping
--   - impression vs impressions naming harmonized at lowercase level

with raw as (
    select * from {{ source('main', 'platform_funnel_events_raw') }}
),

lookup as (
    select taxonomy_type, raw_value, canonical_value
    from {{ source('main', 'taxonomy_lookup_raw') }}
    union all
    select taxonomy_type, raw_value, canonical_value
    from {{ ref('taxonomy_supplement') }}
),

final as (
    select
        event_id,
        campaign_id,

        -- Normalize platform
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'platform' and l.raw_value = f.platform limit 1),
            f.platform
        )                                                           as platform,
        f.platform                                                  as platform_raw,

        event_date,

        -- Lowercase event name for consistent mapping in int_funnel_event_mapping
        lower(trim(f.raw_event_name))                               as raw_event_name,
        f.raw_event_name                                            as raw_event_name_original,

        -- Cast event count: 'unknown' -> NULL
        case
            when f.raw_event_count = 'unknown'
              or f.raw_event_count is null
              or trim(f.raw_event_count) = '' then null
            else cast(f.raw_event_count as integer)
        end                                                         as event_count,

        case
            when f.raw_event_count = 'unknown' then 1
            else 0
        end                                                         as dq_null_event_count,

        f.platform_definition_note

    from raw f
)

select * from final
