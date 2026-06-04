-- stg_taxonomy_lookup
-- Unified taxonomy lookup combining the raw table and the seed supplement.
-- The seed file (taxonomy_supplement.csv) adds missing mappings for:
--   currency, region, on_hand_status, retailer_tier, attribution_window
-- This model is the single source of truth for all taxonomy normalization.

with raw_lookup as (
    select
        taxonomy_type,
        raw_value,
        canonical_value,
        effective_start_date,
        effective_end_date,
        source_system,
        cast(confidence_score as real) as confidence_score
    from {{ source('main', 'taxonomy_lookup_raw') }}
),

seed_supplement as (
    select
        taxonomy_type,
        raw_value,
        canonical_value,
        effective_start_date,
        null                            as effective_end_date,
        source_system,
        cast(confidence_score as real)  as confidence_score
    from {{ ref('taxonomy_supplement') }}
),

-- Raw table takes precedence over seed for any overlapping entries
combined as (
    select *, 'raw' as lookup_source from raw_lookup
    union all
    -- Only include seed rows where raw_lookup doesn't already have the same type+value
    select s.*, 'seed' as lookup_source
    from seed_supplement s
    where not exists (
        select 1 from raw_lookup r
        where r.taxonomy_type = s.taxonomy_type
          and r.raw_value = s.raw_value
    )
)

select * from combined
