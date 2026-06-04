-- stg_campaigns
-- Normalizes marketing campaign metadata.
-- Key issues handled:
--   - Platform naming (Meta/Facebook -> Meta): normalized via taxonomy lookup
--   - funnel_stage (Engagement -> Consideration): normalized via taxonomy lookup, original preserved
--   - region inconsistencies: normalized via taxonomy supplement
--   - campaign_code: normalized to lower_snake_case
--   - mapped_product_key: flags SKU-based keys and unresolvable keys
--     Resolution to canonical product_id happens in int_product_key_resolution

with raw as (
    select * from {{ source('main', 'marketing_campaigns_raw') }}
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
        c.campaign_id,
        c.campaign_name,

        -- Normalize campaign_code to lower_snake_case
        lower(replace(replace(c.campaign_code, '-', '_'), ' ', '_'))    as campaign_code,
        c.campaign_code                                                  as campaign_code_raw,

        -- Normalize platform
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'platform' and l.raw_value = c.platform limit 1),
            c.platform
        )                                                                as platform,
        c.platform                                                       as platform_raw,

        c.start_date,
        c.end_date,

        -- Days duration
        cast(
            julianday(c.end_date) - julianday(c.start_date)
        as integer)                                                      as duration_days,

        -- mapped_product_key as-is; resolution in int_product_key_resolution
        c.mapped_product_key,

        -- Flag SKU-formatted keys (contain 'SKU-')
        case
            when upper(c.mapped_product_key) like 'SKU-%' then 1
            else 0
        end                                                              as dq_product_key_is_sku,

        -- Flag keys that don't exist in products_raw and aren't resolvable as SKUs
        case
            when c.mapped_product_key not in (
                select product_id from {{ source('main', 'products_raw') }}
                union
                select sku from {{ source('main', 'products_raw') }}
                union
                select UPPER(sku) from {{ source('main', 'products_raw') }}
            ) then 1
            else 0
        end                                                              as dq_orphaned_product_key,

        -- Normalize funnel_stage, preserve original
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'funnel_stage' and l.raw_value = c.funnel_stage limit 1),
            c.funnel_stage
        )                                                                as funnel_stage,
        c.funnel_stage                                                   as funnel_stage_raw,

        c.campaign_type,

        -- Normalize region
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'region' and l.raw_value = c.region limit 1),
            c.region
        )                                                                as region

    from raw c
)

select * from final
