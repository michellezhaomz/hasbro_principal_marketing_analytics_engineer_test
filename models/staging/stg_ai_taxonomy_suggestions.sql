-- stg_ai_taxonomy_suggestions
-- Surfaces AI taxonomy suggestions with approval status.
-- CRITICAL: Only suggestions where is_approved = 1 should ever be applied to production models.
-- Unreviewed suggestions (reviewed_flag = 'N') are surfaced here for human review only.
-- Rejected suggestions are preserved for audit purposes.

with raw as (
    select * from {{ source('main', 'ai_taxonomy_suggestions_raw') }}
),

final as (
    select
        suggestion_id,
        source_field,
        raw_value,
        suggested_taxonomy_type,
        suggested_canonical_value,
        cast(model_confidence as real)                              as model_confidence,
        suggested_reason,
        reviewed_flag,
        reviewer_decision,

        -- Approval flag: only accepted reviewed suggestions
        case
            when reviewed_flag = 'Y'
             and lower(reviewer_decision) = 'accepted' then 1
            else 0
        end                                                         as is_approved,

        case
            when reviewed_flag = 'Y'
             and lower(reviewer_decision) = 'rejected' then 1
            else 0
        end                                                         as is_rejected,

        case
            when reviewed_flag = 'N'
              or reviewed_flag is null
              or trim(reviewed_flag) = '' then 1
            else 0
        end                                                         as is_pending_review

    from raw
)

select * from final
