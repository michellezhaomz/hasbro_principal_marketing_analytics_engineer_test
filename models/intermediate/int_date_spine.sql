-- int_date_spine
-- Date dimension covering the full data range.
-- SQLite does not have a native date generation function, so we use a recursive CTE.
-- Provides week_start_date alignment (Monday-based ISO weeks) for joining
-- daily marketing performance to weekly POS data.

with recursive date_series as (
    select date('2021-01-01') as date_day
    union all
    select date(date_day, '+1 day')
    from date_series
    where date_day < date('2024-12-31')
),

final as (
    select
        date_day,

        -- Week start (Monday-based)
        date(date_day, 'weekday 1', '-7 days')                     as week_start_date,

        -- ISO week number (1-52/53)
        cast(strftime('%W', date_day) as integer)                   as week_of_year,

        -- Month
        cast(strftime('%m', date_day) as integer)                   as month_num,
        strftime('%Y-%m', date_day)                                 as year_month,

        -- Quarter
        case
            when cast(strftime('%m', date_day) as integer) between 1 and 3  then 'Q1'
            when cast(strftime('%m', date_day) as integer) between 4 and 6  then 'Q2'
            when cast(strftime('%m', date_day) as integer) between 7 and 9  then 'Q3'
            else 'Q4'
        end                                                         as fiscal_quarter,

        -- Year
        cast(strftime('%Y', date_day) as integer)                   as fiscal_year,

        -- Day of week (1=Monday, 7=Sunday)
        case strftime('%w', date_day)
            when '0' then 7
            else cast(strftime('%w', date_day) as integer)
        end                                                         as day_of_week,

        -- Is this date a Monday (week start)?
        case when strftime('%w', date_day) = '1' then 1 else 0 end  as is_week_start

    from date_series
)

select * from final
