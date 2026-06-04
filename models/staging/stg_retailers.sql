-- stg_retailers
-- Normalizes retailer reference data.
-- Key issues handled:
--   - retailer_tier case inconsistencies: normalized via taxonomy supplement
--   - country variants (US/USA/United States/U.S.): normalized via taxonomy lookup
--   - region variants (NA/North America): normalized via taxonomy supplement
--   - channel case inconsistency (Mass/mass): normalized via taxonomy lookup
--   - R001/R006 near-duplicate: flagged, NOT merged (requires business confirmation)

with raw as (
    select * from {{ source('main', 'retailers_raw') }}
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
        UPPER(r.retailer_id)                                        as retailer_id,
        r.retailer_name,

        -- Normalize channel
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'channel' and l.raw_value = r.channel limit 1),
            r.channel
        )                                                           as channel,

        -- Normalize region
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'region' and l.raw_value = r.region limit 1),
            r.region
        )                                                           as region,

        -- Normalize country
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'country' and l.raw_value = r.country limit 1),
            r.country
        )                                                           as country,

        -- Normalize retailer_tier
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'retailer_tier' and l.raw_value = r.retailer_tier limit 1),
            r.retailer_tier
        )                                                           as retailer_tier,

        -- Flag R006 as a potential duplicate of R001 (Northstar vs North Star Retail)
        -- AI003 suggestion: 0.81 confidence, unreviewed
        -- Do NOT merge until business confirmation received
        case
            when UPPER(r.retailer_id) = 'R006' then 1
            else 0
        end                                                         as dq_potential_duplicate_retailer,

        -- Flag retailer_id R404 which appears in POS data but not in this table
        -- (handled in stg_pos_weekly; noted here for completeness)
        0                                                           as dq_orphaned_in_pos

    from raw r
)

select * from final
