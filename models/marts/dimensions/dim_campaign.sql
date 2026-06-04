-- dim_campaign
-- Canonical campaign dimension. One row per campaign.
-- Resolves mapped_product_key to canonical product_id via int_product_key_resolution.
-- Unresolvable product keys (P4040) are preserved with flag.

with campaigns as (
    select * from {{ ref('stg_campaigns') }}
),

resolution as (
    select * from {{ ref('int_product_key_resolution') }}
),

final as (
    select
        c.campaign_id,
        c.campaign_name,
        c.campaign_code,
        c.campaign_code_raw,
        c.platform,
        c.platform_raw,
        c.start_date,
        c.end_date,
        c.duration_days,
        c.funnel_stage,
        c.funnel_stage_raw,
        c.campaign_type,
        c.region,
        c.mapped_product_key,

        -- Resolved product_id from intermediate layer
        r.resolved_product_id           as product_id,
        r.resolution_method             as product_key_resolution_method,
        r.is_resolvable                 as product_key_is_resolvable,

        c.dq_product_key_is_sku,
        c.dq_orphaned_product_key

    from campaigns c
    left join resolution r
        on c.mapped_product_key = r.raw_key
)

select * from final
