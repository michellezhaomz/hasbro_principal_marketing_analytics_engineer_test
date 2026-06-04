{% macro normalize_via_taxonomy(raw_value_expr, taxonomy_type, fallback_expr=none) %}
{#
  Looks up a raw value in the unified taxonomy lookup (raw + seed supplement).
  Returns the canonical_value if found, otherwise returns the fallback expression
  or the original raw value if no fallback is provided.

  Usage:
    {{ normalize_via_taxonomy('platform', 'platform') }}
    {{ normalize_via_taxonomy('UPPER(retailer_tier)', 'retailer_tier', "'Unknown'") }}
#}
COALESCE(
    (
        SELECT tl.canonical_value
        FROM (
            SELECT taxonomy_type, raw_value, canonical_value
            FROM {{ source('main', 'taxonomy_lookup_raw') }}
            UNION ALL
            SELECT taxonomy_type, raw_value, canonical_value
            FROM {{ ref('taxonomy_supplement') }}
        ) tl
        WHERE tl.taxonomy_type = '{{ taxonomy_type }}'
          AND tl.raw_value = {{ raw_value_expr }}
        LIMIT 1
    ),
    {% if fallback_expr %}{{ fallback_expr }}{% else %}{{ raw_value_expr }}{% endif %}
)
{% endmacro %}
