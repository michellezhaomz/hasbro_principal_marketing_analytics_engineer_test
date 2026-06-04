-- stg_promo_calendar
-- Normalizes promotion calendar data.
-- Key issues handled:
--   - expected_discount_pct 'N/A' -> NULL with flag
--   - Orphaned retailer_id R999 flagged
--   - retailer_id normalized to UPPER

with raw as (
    select * from {{ source('main', 'promo_calendar_raw') }}
),

final as (
    select
        promo_id,
        UPPER(retailer_id)                                          as retailer_id,
        product_key,
        promo_start_date,
        promo_end_date,
        promo_type,

        case
            when expected_discount_pct = 'N/A'
              or expected_discount_pct is null
              or trim(cast(expected_discount_pct as text)) = '' then null
            else cast(expected_discount_pct as real)
        end                                                         as expected_discount_pct,

        case
            when expected_discount_pct = 'N/A' then 1
            else 0
        end                                                         as dq_null_discount_pct,

        funding_source,

        -- Flag orphaned retailer_id (R999 not in retailers_raw)
        case
            when UPPER(retailer_id) not in (
                select UPPER(retailer_id) from {{ source('main', 'retailers_raw') }}
            ) then 1
            else 0
        end                                                         as dq_orphaned_retailer_id

    from raw
)

select * from final
