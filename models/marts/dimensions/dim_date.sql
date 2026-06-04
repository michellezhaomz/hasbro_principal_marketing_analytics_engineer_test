-- dim_date
-- Standard date dimension materialized from int_date_spine.
-- Used to align daily marketing performance data to weekly POS grain.

select * from {{ ref('int_date_spine') }}
