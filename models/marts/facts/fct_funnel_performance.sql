-- fct_funnel_performance
-- Canonical funnel performance fact. One row per (campaign_id, platform, event_date, canonical_stage, canonical_event_type).
-- Platform-specific event names are mapped to canonical stages via int_funnel_event_mapping.
-- Raw event names are preserved for auditability.
-- Rows with AI-suggested mappings are flagged requires_human_review = 1.

with funnel as (
    select * from {{ ref('int_funnel_event_mapping') }}
),

campaigns as (
    select campaign_id, product_id
    from {{ ref('dim_campaign') }}
)

select
    f.event_id,
    f.campaign_id,
    c.product_id,
    f.platform,
    f.platform_raw,
    f.event_date,

    -- Canonical funnel stage and event type
    f.canonical_stage,
    f.canonical_event_type,

    -- Raw values preserved for audit
    f.raw_event_name,
    f.raw_event_name_original,

    f.event_count,
    f.platform_definition_note,

    f.dq_unmapped_event,
    f.dq_null_event_count,
    f.requires_human_review

from funnel f
left join campaigns c on f.campaign_id = c.campaign_id
