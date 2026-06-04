-- stg_products
-- Normalizes product reference data.
-- Key issues handled:
--   - Duplicate product_id P1002: deduplicated, keeping the record with proper ISO date and uppercase SKU
--   - Mixed case product_status: normalized via taxonomy lookup
--   - Inconsistent launch_date formats: standardized to ISO; 'bad-date' set to NULL with flag
--   - Mixed case SKU: normalized to UPPER
--   - age_grade 'N/A' string: treated as NULL

with raw as (
    select * from {{ source('main', 'products_raw') }}
),

-- Rank duplicates: prefer uppercase SKU and valid ISO date format
deduped as (
    select
        *,
        row_number() over (
            partition by product_id
            order by
                -- Prefer records where SKU is already uppercase
                case when sku = UPPER(sku) then 0 else 1 end,
                -- Prefer valid ISO date format (YYYY-MM-DD, length 10, no slashes)
                case when length(launch_date) = 10 and launch_date not like '%/%' and launch_date != 'bad-date' then 0 else 1 end
        ) as row_num
    from raw
),

final as (
    select
        product_id,
        UPPER(sku)                                              as sku,
        product_name,
        category,
        -- Normalize category spelling (Creative vs Creativity)
        case
            when lower(category) in ('creativity', 'creative') then 'Creative'
            else category
        end                                                     as category_normalized,
        franchise,
        -- Normalize product_status via taxonomy lookup
        coalesce(
            (select canonical_value from {{ source('main', 'taxonomy_lookup_raw') }}
             where taxonomy_type = 'product_status' and raw_value = product_status limit 1),
            product_status
        )                                                       as product_status,

        -- Normalize launch_date: handle slash format, null out unparseable values
        case
            when launch_date = 'bad-date'       then null
            when launch_date like '%/%'         then replace(launch_date, '/', '-')
            when length(launch_date) = 10       then launch_date
            else null
        end                                                     as launch_date,

        case when launch_date = 'bad-date' then 1 else 0 end   as dq_invalid_launch_date,

        -- age_grade: treat 'N/A' as NULL
        case when age_grade = 'N/A' then null else age_grade end as age_grade,

        -- Flag that this record was deduplicated
        case when row_num > 1 then 1 else 0 end                as dq_was_duplicate,

        row_num

    from deduped
    where row_num = 1
)

select
    product_id,
    sku,
    product_name,
    category_normalized                                         as category,
    franchise,
    product_status,
    launch_date,
    age_grade,
    dq_invalid_launch_date,
    dq_was_duplicate
from final
