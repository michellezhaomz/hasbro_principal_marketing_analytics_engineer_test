# Model Design Reference

Detailed model inventory for engineering reference. For the business-facing summary, see the main `README.md`.

---

## Architectural Decisions

The model design intentionally prioritizes transparency, governance, and maintainability over aggressive automation.

### Shared Business Logic Is Centralized

Several business concepts appear across multiple domains, including product identifiers, retailer identifiers, and funnel taxonomies. Rather than resolving these independently within downstream models, shared logic is centralized in intermediate models:

- `int_product_key_resolution` — resolves product_id, SKU, and unknown keys to a canonical product_id
- `int_funnel_event_mapping` — maps platform-specific event names to canonical funnel stages and event types
- `stg_retailers` — surfaces the R001/R006 potential duplicate with a flag rather than embedding retailer dedup logic in each downstream model

This reduces duplicated logic and ensures consistent business definitions across all reporting outputs.

### Data Quality Issues Are Surfaced Rather Than Hidden

Where data quality issues exist, the preferred approach is to preserve source records and expose issue flags rather than silently correcting or excluding data. Examples include:

- Potential retailer duplicates (`dq_potential_duplicate_retailer`)
- Orphaned product references (`dq_orphaned_product_key`)
- Unresolved taxonomy mappings (`dq_unmapped_event`)
- Missing baseline records (`dq_baseline_missing`)

This allows downstream consumers to understand both the metric and the confidence level associated with it. `mart_data_quality_summary` makes all flags queryable in one place.

### Taxonomy Is Treated as a Governed Asset

Platform names, funnel stages, event names, regions, currencies, and retailer attributes are standardized through governed taxonomy mappings (`stg_taxonomy_lookup`) rather than embedded directly into model logic. New mappings are added to `seeds/taxonomy_supplement.csv` via a reviewed pull request. This approach simplifies maintenance and creates a clear ownership model for future taxonomy changes. See `docs/TAXONOMY_GOVERNANCE.md` for the full governance framework.

### Attribution Windows Remain Explicit

Attribution windows are preserved as dimensions within `fct_marketing_performance`. This prevents accidental aggregation across incompatible attribution methodologies. The standard reporting window (`7d_click`) is enforced via `is_standard_attribution_window = 1`, while the full window breakdown remains available for analysts who need it. See `docs/METRIC_DEFINITIONS.md` for the attribution window policy.

### Lift Is Designed as Observational Measurement

The available dataset does not support causal inference because no experimental control group exists. The lift framework in `fct_marketing_lift` therefore measures observed performance relative to expected baseline performance while explicitly surfacing confounding factors:

- Active retail promotions (`is_confirmed_promo_week`)
- Inventory constraints (`is_oos`, `is_low_stock`)
- Missing or conflicting baseline data (`dq_baseline_missing`, `dq_multiple_baseline_methods`)
- Unresolvable product or retailer mappings

Every lift row carries a `lift_confidence` classification (`clean`, `confounded`, `incomplete`, `unresolvable`) so analysts always know which rows support defensible conclusions and which require caveats.

---

## Staging Layer (10 models)

All staging models are materialized as **tables** in this SQLite implementation. (In production on Snowflake/BigQuery/Redshift these would be views — SQLite does not support cross-schema view references.) Each model is 1:1 with a raw source table. No cross-table joins except to `stg_taxonomy_lookup` for normalization. All DQ issues are flagged with `dq_` prefixed columns rather than silently dropped.

| Model | Source Table | Key Transformations | DQ Flags Added |
|---|---|---|---|
| `stg_products` | `products_raw` | Dedup P1002 (keep uppercase SKU + ISO date), normalize `product_status`, `UPPER(sku)`, cast `launch_date` | `dq_invalid_launch_date`, `dq_was_duplicate` |
| `stg_retailers` | `retailers_raw` | Normalize `retailer_tier`, `country`, `region`, `channel` via lookup | `dq_potential_duplicate_retailer` (R006) |
| `stg_taxonomy_lookup` | `taxonomy_lookup_raw` + `taxonomy_supplement` seed | Union raw + seed; seed rows only included where raw doesn't already cover | — |
| `stg_campaigns` | `marketing_campaigns_raw` | Normalize `platform`, `funnel_stage`, `region`; snake_case `campaign_code`; flag non-product_id keys | `dq_product_key_is_sku`, `dq_orphaned_product_key` |
| `stg_marketing_performance` | `marketing_performance_raw` | Cast `spend` (N/A→NULL), normalize `currency`, `attribution_window`, `platform`; exclude MPDUP1 | `dq_null_spend`, `dq_duplicate_record` |
| `stg_funnel_events` | `platform_funnel_events_raw` | Normalize `platform`; lowercase `raw_event_name`; cast `raw_event_count` (unknown→NULL) | `dq_null_event_count` |
| `stg_pos_weekly` | `retail_pos_weekly_raw` | `UPPER(retailer_id)`; normalize `promo_flag`, `on_hand_status`, `country`, `region`; flag negative units; dedup POSDUP1 (keep lower units row) | `is_return_adjustment`, `dq_units_sales_sign_mismatch`, `dq_product_key_is_sku`, `dq_orphaned_product_key`, `dq_orphaned_retailer_id`, `dq_duplicate_grain` |
| `stg_pos_baseline` | `pos_baseline_history_raw` | Cast `avg_weekly_units` (unknown→NULL); `UPPER(retailer_id)`; window function for multiple-method flag | `dq_null_avg_units`, `dq_duplicate_baseline`, `dq_multiple_baseline_methods`, `dq_product_key_is_sku` |
| `stg_promo_calendar` | `promo_calendar_raw` | Cast `expected_discount_pct` (N/A→NULL); `UPPER(retailer_id)`; flag R999 | `dq_orphaned_retailer_id`, `dq_null_discount_pct` |
| `stg_ai_taxonomy_suggestions` | `ai_taxonomy_suggestions_raw` | Add `is_approved`, `is_rejected`, `is_pending_review` boolean flags | — |

---

## Intermediate Layer (3 models)

All intermediate models are materialized as **tables** in this SQLite implementation. (Would be views in production.) They exist to solve cross-table problems once for all downstream consumers.

### `int_product_key_resolution`
**Purpose:** Resolve the three product key formats (product_id, SKU, unknown) to a canonical `product_id`.

**Resolution order:**
1. Direct match on `product_id` → `resolution_method = 'product_id_match'`
2. `UPPER(raw_key)` match on `sku` in `stg_products` → `resolution_method = 'sku_match'`
3. No match → `resolution_method = 'unresolvable'`, `is_resolvable = 0`

**Resolved:**
- `SKU-BETA-002` → `P1002` (sku_match)

**Unresolvable:**
- `P4040` → no product record exists

### `int_funnel_event_mapping`
**Purpose:** Map every `(platform, raw_event_name)` pair to a canonical funnel stage and event type.

**Canonical stages:** `awareness`, `consideration`, `conversion`
**Canonical event types:** `impression`, `video_view`, `click`, `page_view`, `purchase`, `engaged_view`

Rows with `dq_unmapped_event = 1` indicate a new event name not yet in the mapping table — these need to be added manually.

Rows with `requires_human_review = 1` use AI-suggested mappings that have not been confirmed by a human reviewer (currently: TikTok `complete_payment → purchase`, AI002).

### `int_date_spine`
**Purpose:** Generate a continuous date series (2021-01-01 to 2024-12-31) for grain alignment.

Weekly POS data uses `week_start_date`; daily marketing performance uses `activity_date`. The date spine provides `week_start_date` for every `date_day`, enabling daily → weekly aggregation in reporting models without losing days at week boundaries.

---

## Dimension Layer (4 models)

All dimensions are materialized as tables.

| Model | Grain | Source | Notes |
|---|---|---|---|
| `dim_product` | One row per `product_id` | `stg_products` | Includes all products. P9999 included; P4040 not present (no product record). |
| `dim_retailer` | One row per `retailer_id` | `stg_retailers` | R006 preserved with `dq_potential_duplicate_retailer = 1`. Do not merge until confirmed. |
| `dim_campaign` | One row per `campaign_id` | `stg_campaigns` + `int_product_key_resolution` | `product_id` is resolved. CAMP006 resolves to P1002 via SKU. CAMP007 has `product_key_is_resolvable = 0`. |
| `dim_date` | One row per `date_day` | `int_date_spine` | Covers 2021-01-01 to 2024-12-31. Includes `week_start_date`, `fiscal_quarter`, `fiscal_year`. |

---

## Fact Layer (5 models)

All facts are materialized as tables.

### `fct_marketing_performance`
**Grain:** `(campaign_id, platform, activity_date, attribution_window)`

**Key design decision:** Attribution window is a dimension, not something to aggregate over. Aggregating across windows double-counts conversions. Always filter to a single window for ROAS calculations (`is_standard_attribution_window = 1`).

**Pre-calculated metrics:** `cpm`, `cpc`, `ctr`, `cvr`, `roas` — NULL-safe, available for direct BI consumption.

### `fct_funnel_performance`
**Grain:** `(event_id)` — one row per platform funnel event record.

Maps raw events to canonical stages via `int_funnel_event_mapping`. Rows with `dq_unmapped_event = 1` represent events with no canonical mapping — monitor and add to the mapping table as needed.

### `fct_pos_weekly`
**Grain:** `(retailer_id, product_id, week_start_date)` — after deduplication.

Return/adjustment rows (`is_return_adjustment = 1`) are included but should be excluded for demand analysis. They are preserved rather than dropped because they represent real transactions that may be needed for reconciliation.

Promo context is joined from `stg_promo_calendar` to produce `is_confirmed_promo_week` — a combined flag that is true when either the POS record's `promo_flag` indicates a promo OR the promo calendar has an active promotion for that retailer/product/week.

### `fct_pos_baseline`
**Grain:** `(retailer_id, product_id, baseline_method)` — one row per baseline variant.

All baseline methods are preserved. Use `is_preferred_method = 1` to filter to the `var('default_baseline_method')` preference. The lift model handles fallback automatically when the preferred method is unavailable.

### `fct_marketing_lift`
**Grain:** `(campaign_id, product_id, retailer_id, week_start_date)`

**Campaign window:** Weeks where `week_start_date` falls between `campaign.start_date` and `campaign.end_date` (inclusive). This logic is inlined rather than in a separate intermediate model given its limited scope.

**Lift formula:**
```
expected_units = avg_weekly_units × seasonality_index
absolute_unit_lift = actual_units − expected_units
pct_unit_lift = absolute_unit_lift / expected_units
```

**`lift_confidence` classification:**
- `clean` — no promo, not OOS, baseline exists, no DQ flags
- `confounded` — active promo OR OOS
- `incomplete` — baseline missing or has DQ issues
- `unresolvable` — product or retailer key cannot be resolved

---

## Reporting Layer (2 models)

### `rpt_marketing_effectiveness`
**Grain:** `(campaign_id, product_id, retailer_id, week_start_date)`

Joins all fact and dimension models into a single pre-aggregated view. Marketing metrics are rolled up from daily to weekly using `dim_date.week_start_date`. Funnel metrics are aggregated by canonical stage.

This is the primary model for executive reporting and BI tool consumption.

### `mart_data_quality_summary`
**Grain:** `(source_table, dq_flag)`

Unions all DQ flag counts from staging models plus lift confidence distribution from `fct_marketing_lift`. Provides a queryable health check on the data pipeline. Expected to be queried after each `dbt run` to confirm issue counts have not grown unexpectedly.
