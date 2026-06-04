-- stg_pos_weekly
-- Normalizes weekly POS data.
-- Key issues handled:
--   - retailer_id: normalized to UPPER; R404 flagged as orphaned
--   - product_key: SKU-based and unresolvable keys flagged (resolved in int_product_key_resolution)
--   - Negative units_sold: flagged as return/adjustment transactions
--   - units_sold / gross_sales sign mismatch: negative units with positive sales flagged
--   - promo_flag: normalized to boolean (Y/1 -> true, N/0/No -> false)
--   - on_hand_status: normalized via taxonomy supplement
--   - country/region: normalized via taxonomy lookup
--   - Duplicate grain: any retailer/product/week appearing more than once flagged and deduplicated
--   - retailer_name column dropped (derived from dim_retailer in downstream models)

with raw as (
    select * from {{ source('main', 'retail_pos_weekly_raw') }}
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
        UPPER(retailer_id)                                              as retailer_id_clean,

        -- Flag any retailer/product/week combination appearing more than once
        case
            when count(*) over (
                partition by UPPER(retailer_id), product_key, week_start_date
            ) > 1 then 1
            else 0
        end                                                             as dq_duplicate_grain,

        -- Numeric casts for comparison
        cast(units_sold as real)                                    as units_num,
        cast(gross_sales as real)                                   as sales_num

    from raw
),

deduped as (
    select
        *,
        row_number() over (
            partition by retailer_id_clean, product_key, week_start_date
            order by
                -- For any duplicate grain: keep lower units row (conservative default)
                cast(units_sold as real) asc,
                pos_id asc
        ) as grain_row_num
    from flagged
),

final as (
    select
        pos_id,
        retailer_id_clean                                               as retailer_id,

        product_key,

        -- Flag SKU-based product keys
        case
            when upper(product_key) like 'SKU-%' then 1
            else 0
        end                                                             as dq_product_key_is_sku,

        -- Flag orphaned product keys
        case
            when product_key not in (
                select product_id from {{ source('main', 'products_raw') }}
                union
                select UPPER(sku) from {{ source('main', 'products_raw') }}
            ) then 1
            else 0
        end                                                             as dq_orphaned_product_key,

        -- Flag orphaned retailer_id
        case
            when retailer_id_clean not in (
                select UPPER(retailer_id) from {{ source('main', 'retailers_raw') }}
            ) then 1
            else 0
        end                                                             as dq_orphaned_retailer_id,

        week_start_date,

        units_num                                                       as units_sold,

        -- Flag negative units (return/adjustment transactions)
        case when units_num < 0 then 1 else 0 end                      as is_return_adjustment,

        -- Flag sign mismatch: negative units but positive sales
        case
            when units_num < 0 and sales_num > 0 then 1
            else 0
        end                                                             as dq_units_sales_sign_mismatch,

        sales_num                                                       as gross_sales,

        case
            when inventory_units is null or trim(cast(inventory_units as text)) = '' then null
            else cast(inventory_units as integer)
        end                                                             as inventory_units,

        case
            when regular_price is null or trim(cast(regular_price as text)) = '' then null
            else cast(regular_price as real)
        end                                                             as regular_price,

        case
            when promo_price is null or trim(cast(promo_price as text)) = '' then null
            else cast(promo_price as real)
        end                                                             as promo_price,

        -- Normalize promo_flag to boolean integer (1=yes, 0=no)
        case
            when upper(promo_flag) in ('Y', 'YES', '1') then 1
            when upper(promo_flag) in ('N', 'NO', '0')  then 0
            else null
        end                                                             as is_promo_week,

        -- Normalize on_hand_status
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'on_hand_status'
               and l.raw_value = d.on_hand_status limit 1),
            'unknown'
        )                                                               as on_hand_status,
        d.on_hand_status                                                as on_hand_status_raw,

        -- Derived flags for lift confound detection
        case
            when coalesce(
                (select l.canonical_value from lookup l
                 where l.taxonomy_type = 'on_hand_status'
                   and l.raw_value = d.on_hand_status limit 1),
                'unknown'
            ) = 'out_of_stock' then 1
            else 0
        end                                                             as is_oos,

        case
            when coalesce(
                (select l.canonical_value from lookup l
                 where l.taxonomy_type = 'on_hand_status'
                   and l.raw_value = d.on_hand_status limit 1),
                'unknown'
            ) = 'low_stock' then 1
            else 0
        end                                                             as is_low_stock,

        -- Normalize region
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'region' and l.raw_value = d.region limit 1),
            d.region
        )                                                               as region,

        -- Normalize country
        coalesce(
            (select l.canonical_value from lookup l
             where l.taxonomy_type = 'country' and l.raw_value = d.country limit 1),
            d.country
        )                                                               as country,

        dq_duplicate_grain,
        grain_row_num

    from deduped d
    -- Exclude all but the first row for duplicate grains (conservative: lower units)
    where grain_row_num = 1
)

select
    pos_id,
    retailer_id,
    product_key,
    week_start_date,
    units_sold,
    gross_sales,
    inventory_units,
    regular_price,
    promo_price,
    is_promo_week,
    on_hand_status,
    on_hand_status_raw,
    is_oos,
    is_low_stock,
    region,
    country,
    is_return_adjustment,
    dq_product_key_is_sku,
    dq_orphaned_product_key,
    dq_orphaned_retailer_id,
    dq_units_sales_sign_mismatch,
    dq_duplicate_grain
from final