-- int_product_key_resolution
-- Resolves the three-way product identifier problem across campaigns, POS, and baselines.
-- Raw data uses product_id (P1001), SKU (SKU-BETA-002), or unknown keys (P4040).
-- This model builds a unified resolution map so all downstream models join here
-- instead of each independently resolving product keys.
--
-- Resolution logic:
--   1. Direct match on product_id -> resolved
--   2. Match on UPPER(sku) -> resolved to product_id
--   3. No match -> unresolvable (is_resolvable = 0)

with products as (
    select product_id, sku
    from {{ ref('stg_products') }}
),

-- Collect all distinct product keys appearing across source tables
all_keys as (
    select mapped_product_key as raw_key from {{ ref('stg_campaigns') }}
    union
    select product_key as raw_key from {{ ref('stg_pos_weekly') }}
    union
    select product_key as raw_key from {{ ref('stg_pos_baseline') }}
),

resolved as (
    select
        k.raw_key,

        -- Attempt direct product_id match
        case
            when p_direct.product_id is not null then p_direct.product_id
            -- Attempt SKU match (uppercase)
            when p_sku.product_id is not null then p_sku.product_id
            else null
        end                                                         as resolved_product_id,

        case
            when p_direct.product_id is not null then 'product_id_match'
            when p_sku.product_id is not null    then 'sku_match'
            else 'unresolvable'
        end                                                         as resolution_method,

        case
            when p_direct.product_id is not null then 1
            when p_sku.product_id is not null    then 1
            else 0
        end                                                         as is_resolvable

    from all_keys k

    -- Direct product_id match
    left join products p_direct
        on k.raw_key = p_direct.product_id

    -- SKU match (case-insensitive)
    left join products p_sku
        on UPPER(k.raw_key) = p_sku.sku
        and p_direct.product_id is null  -- only use SKU match if direct match failed
)

select
    raw_key,
    resolved_product_id,
    resolution_method,
    is_resolvable
from resolved
