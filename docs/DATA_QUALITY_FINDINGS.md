# Principal Marketing Analytics Engineer Assessment
## Data Quality & Issue Inventory

**Database:** `principal_marketing_analytics_engineer_test.sqlite`  
**Prepared by:** Data Audit  
**Purpose:** Pre-dbt issue inventory — review and confirm before model build begins

---

## Summary

The database contains **10 raw tables** across four domains: Product/Retail Reference, Marketing, POS, and Lift/Baseline. The data is intentionally imperfect. This document catalogs every confirmed issue by table, categorizes it by severity, and notes the recommended treatment. No data has been modified.

**Issue count by severity:**

| Severity | Count |
|---|---|
| 🔴 Critical (blocks joins or lift calculations) | 14 |
| 🟡 Medium (causes metric distortion if unhandled) | 18 |
| 🟢 Low (cosmetic / needs documentation) | 9 |

---

## Table-by-Table Issues

---

### 1. `products_raw`
**Row count:** 10

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| P-1 | Duplicate product_id | 🔴 Critical | `P1002` appears twice with different SKU casing (`sku-beta-002` vs `SKU-BETA-002`), different category spellings (`Creative` vs `Creativity`), and different `launch_date` formats. One is the authoritative record; the other is a stale or erroneous copy. | Deduplicate — keep the record with proper ISO date format and uppercase SKU (`SKU-BETA-002`, `2024-02-01`). Flag the dupe in a dbt test. |
| P-2 | `product_status` case inconsistency | 🟡 Medium | Three variants for the same value: `Active`, `active`, `ACTIVE`. | Normalize to title case via `taxonomy_lookup_raw` (mappings for `active` and `ACTIVE` already exist). |
| P-3 | Inconsistent `launch_date` formats | 🟡 Medium | Mix of `YYYY-MM-DD` (standard), `YYYY/MM/DD` (P1002), and `bad-date` (P1007). | Cast all to `DATE` type; flag `bad-date` as `NULL` with a data quality flag column. |
| P-4 | Unparseable `launch_date` = `'bad-date'` | 🔴 Critical | P1007 (`Eta Battle Arena`) has a literal string `bad-date` for launch date. This product appears in POS data and campaigns. | Set to `NULL`; surface in a `stg_products` data quality flag. Do not impute without business input. |
| P-5 | `age_grade` is `NULL` for P1008 and `N/A` (string) for P9999 | 🟢 Low | Incomplete reference data; likely not needed for lift calculations. | Treat `N/A` as `NULL` in staging. |
| P-6 | SKU case inconsistency | 🟡 Medium | `sku-beta-002` vs `SKU-BETA-002` — same product, different casing. Cross-table joins on SKU will fail silently. | Normalize all SKUs to `UPPER()` in staging. |
| P-7 | `P9999 / Omega Mystery Pack` has `category = 'Unknown'` | 🟢 Low | Likely a placeholder. No campaigns or POS records reference P9999, but it could appear in future loads. | Flag as unclassified. |

---

### 2. `retailers_raw`
**Row count:** 6

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| R-1 | Duplicate retailer (`Northstar Retail` / `North Star Retail`) | 🔴 Critical | `R001 = Northstar Retail` and `R006 = North Star Retail` appear to be the same physical retailer with a name spelling variant. `ai_taxonomy_suggestions_raw` (AI003) flags this as a near-duplicate with 0.81 confidence, but it is unreviewed. If treated as two retailers, lift calculations will be split incorrectly. | Requires human validation before dedup. If confirmed the same: consolidate to `R001`, retire `R006`. Hold `R006` records until resolved. |
| R-2 | `retailer_tier` case/format inconsistency | 🟡 Medium | Four variants: `Tier 1`, `tier1`, `Tier 2`, `Tier One`. | Normalize to `Tier 1` / `Tier 2` / `Tier 3` in staging. |
| R-3 | `country` inconsistency | 🟡 Medium | Four values: `US`, `USA`, `United States`, `U.S.` — all refer to the same country. | Normalize to `US` using taxonomy lookup (mappings for `USA` and `United States` already exist; add `U.S.`). |
| R-4 | `region` inconsistency | 🟡 Medium | `NA` and `North America` used interchangeably. | Normalize to `North America`. The abbreviation `NA` is ambiguous (could mean "not applicable"). |
| R-5 | `channel` case inconsistency | 🟢 Low | `Mass` and `mass` coexist. Taxonomy lookup has both mapped to `Mass Retail`. | Apply lookup in staging. |

---

### 3. `marketing_campaigns_raw`
**Row count:** 7

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| MC-1 | Platform naming inconsistency | 🟡 Medium | `Meta` and `Meta/Facebook` both used across campaigns. `CAMP006` uses `Meta/Facebook`. | Normalize via taxonomy lookup (`Meta/Facebook → Meta`). |
| MC-2 | Orphaned `mapped_product_key` — SKU used instead of product_id | 🔴 Critical | `CAMP006` has `mapped_product_key = 'SKU-BETA-002'` (a SKU) rather than a product_id (`P1002`). This join will fail against `products_raw`. | Resolve in staging: look up SKU in `products_raw`, replace with canonical `product_id`. |
| MC-3 | Orphaned `mapped_product_key` — non-existent product | 🔴 Critical | `CAMP007` has `mapped_product_key = 'P4040'`, which does not exist in `products_raw`. This is a `Legacy` campaign. | Cannot be resolved from available data. Flag as unresolvable; exclude from lift analysis with a note. |
| MC-4 | Unknown platform (`PlatformX`) | 🟡 Medium | `CAMP007` uses `PlatformX`, which maps to `Unknown Platform` in taxonomy with confidence 0.20. An AI suggestion (AI005) proposed TikTok but was **rejected** by a reviewer. | Keep as `Unknown Platform`. Do not accept the rejected AI suggestion. |
| MC-5 | `campaign_code` format inconsistency | 🟢 Low | Mix of `snake_case` (e.g., `spring_launch_alpha`) and `UPPER-KEBAB-CASE` (e.g., `SPRING-SEARCH-BETA`). Not a join-breaking issue but breaks downstream code lookups. | Normalize to `lower_snake_case` in staging. |
| MC-6 | `region` inconsistency (`NA` vs `North America` vs `US`) | 🟡 Medium | Same ambiguity as in retailers — `NA` is ambiguous. `US` and `North America` are used for different campaigns. | Normalize using taxonomy lookup. Add explicit `country` field if granularity needed. |
| MC-7 | `funnel_stage` inconsistency (`Engagement` → `Consideration`) | 🟡 Medium | Taxonomy lookup maps `Engagement` to `Consideration` (confidence 0.75). This is a business judgment call. | Apply lookup but surface original value and confidence score in staging model so analysts can review. |

---

### 4. `marketing_performance_raw`
**Row count:** 137

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| MP-1 | `spend` contains `'N/A'` string (non-numeric) | 🔴 Critical | 3 rows (`MP00001`, `MP00024`, `MP00031`) have `spend = 'N/A'`. Any aggregation will silently drop or error on these. | Cast to `FLOAT`; treat `'N/A'` as `NULL`. Add a dbt `not_null` test with a threshold to flag if count grows. |
| MP-2 | `currency` inconsistency | 🟡 Medium | Three variants: `USD`, `usd`, `US Dollars` — all 137 rows represent the same currency. | Normalize to `USD` in staging. Taxonomy lookup does not include this mapping — needs to be added. |
| MP-3 | `attribution_window` inconsistency | 🟡 Medium | Five variants: `1d_click`, `7-day click`, `view_through_1d`, `7d_click`, `platform_default`. `7-day click` and `7d_click` appear to be the same window on the same platform. `platform_default` is undefined. | Normalize to a canonical set (e.g., `1d_click`, `7d_click`, `view_through_1d`, `unknown`). Do not aggregate across different attribution windows without flagging. |
| MP-4 | Duplicate performance record (conflicting spend) | 🔴 Critical | Two rows with `performance_id = 'MPDUP1'` for `CAMP001 / Meta / 2024-03-15`, with spend values of `$900.00` and `$925.00`. A third row (`MP00013`) exists for the same key with spend `$272.25`. It is unclear whether MPDUP1 is a corrected restatement or an accidental double-load. | Cannot auto-resolve. Flag for business review. For now, exclude `MPDUP1` rows from aggregation and use `MP00013`. Document assumption. |
| MP-5 | `link_clicks` and `video_views` columns are sometimes blank vs. zero | 🟢 Low | Meta rows have blank `video_views`; YouTube rows have blank `link_clicks`. This is expected (platform-specific metrics) but needs to be handled so `NULL` is not treated as `0`. | Treat blanks as `NULL` in staging, not `0`. Apply only in the context of the relevant platform. |

---

### 5. `platform_funnel_events_raw`
**Row count:** 93

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| FE-1 | Platform-specific event names — no canonical funnel stage mapping | 🔴 Critical | Each platform uses its own event vocabulary: Meta uses `link_click` / `landing_page_view`, TikTok uses `complete_payment`, YouTube uses `engaged_view`. These cannot be compared without a canonical mapping. | Build a `funnel_event_lookup` in staging that maps raw event names to canonical stages (Awareness / Consideration / Conversion). Use `taxonomy_lookup_raw` where it exists; fill gaps manually. AI002 suggests `complete_payment → purchase` (0.87, unreviewed) — requires human sign-off before applying. |
| FE-2 | `Meta` and `Meta/Facebook` both appear as platforms | 🟡 Medium | `CAMP001` events use `Meta`; `CAMP006` events use `Meta/Facebook`. Both should map to the same canonical platform. | Apply platform normalization from taxonomy lookup. |
| FE-3 | One row with `raw_event_count = 'unknown'` | 🔴 Critical | `FE_BAD` has a non-numeric event count. Cannot be used in funnel volume calculations. | Cast to `INTEGER`; treat `'unknown'` as `NULL`. Add `not_null` and `is_numeric` tests. |
| FE-4 | `impression` vs `impressions` naming across platforms | 🟢 Low | Meta/Instagram/TikTok use `impression` (singular); Google/YouTube use `impressions` (plural). These should map to the same canonical event. | Include both in the funnel event lookup pointing to the same canonical value. |

---

### 6. `retail_pos_weekly_raw`
**Row count:** 579

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| POS-1 | Negative `units_sold` on 10 rows | 🔴 Critical | 10 rows have negative unit values (e.g., -67, -150, -152). These appear to be returns or adjustments rather than sales weeks. Retaining them as-is will understate sales in lift calculations. | Flag with an `is_return_adjustment` boolean. Exclude from baseline and lift numerator by default; document that they may represent legitimate adjustments. Never silently set to `NULL` or zero. |
| POS-2 | `gross_sales` is positive even on rows with negative `units_sold` | 🟡 Medium | The 10 rows with negative units have positive sales values (e.g., -67 units but +$1,627.43 sales). This is internally inconsistent — either units or sales is wrong. | Flag as data integrity issue. Cannot resolve without source system clarification. Hold out of lift analysis. |
| POS-3 | `promo_flag` has four distinct values: `Y`, `N`, `No`, `0` | 🟡 Medium | Taxonomy lookup covers `Y → Yes`, `N → No`, `0 → No`. All should normalize to boolean `true/false`. | Apply taxonomy lookup in staging. Add dbt `accepted_values` test post-normalization. |
| POS-4 | `on_hand_status` has inconsistent values | 🟡 Medium | Five variants: `OOS`, blank (empty string), `In Stock`, `low stock`, `in_stock`. Blank is ambiguous — unknown vs. not applicable vs. in stock. | Normalize: `in_stock / In Stock → in_stock`, `OOS → out_of_stock`, `low stock → low_stock`, blank → `unknown`. Flag OOS weeks separately in lift model (OOS confounds lift measurement). |
| POS-5 | `retailer_id` case inconsistency | 🔴 Critical | Mix of uppercase (`R001`) and lowercase (`r001`, `r002`, `r003`, `r004`) for the same retailers. Cross-table joins using retailer_id will miss matches unless normalized first. Also one `R404` row that has no match in `retailers_raw`. | Normalize to `UPPER()` in staging. Flag `R404` as orphaned — investigate or exclude. |
| POS-6 | Orphaned `product_key` values | 🔴 Critical | Two product key values appear in POS records that don't exist in `products_raw`: `SKU-BETA-002` (a SKU for P1002) and `P4040` (unknown product). | Attempt SKU-to-product_id resolution for `SKU-BETA-002`; flag `P4040` as unresolvable. Mirror the same treatment used in campaigns. |
| POS-7 | `country` inconsistency | 🟡 Medium | Three variants: `United States`, `USA`, `US` — already covered by taxonomy lookup. | Apply lookup. |
| POS-8 | `region` inconsistency (`NA` vs `North America`) | 🟢 Low | Same issue as other tables. | Apply normalization. |
| POS-9 | Duplicate grain row (`POSDUP1`) | 🔴 Critical | Two rows share `pos_id = 'POSDUP1'` for `R001 / P1001 / 2024-03-18` with different unit and sales values (180 units/$3,598 vs 190 units/$3,798). Both rows also share the same `pos_id`. It is unclear which is authoritative. | Cannot auto-resolve. For now, hold both and use the most conservative (lower) value for lift calculations. Flag for source system review. |
| POS-10 | `retailer_name` in POS does not always match `retailers_raw` | 🟢 Low | POS table carries a `retailer_name` field that may drift from the master name in `retailers_raw`. `BrightCart Online` in POS vs `BrightCart Online` in retailers — OK here, but the column is redundant and a future drift risk. | Drop `retailer_name` from staging POS model; derive it from `retailers_raw` via join on `retailer_id`. |

---

### 7. `pos_baseline_history_raw`
**Row count:** 26

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| BL-1 | Duplicate baseline for `R001 / P1001` with conflicting values and methods | 🔴 Critical | `BLDUP` appears twice for `R001 / P1001 / 2024-01-01 → 2024-02-25`: one record uses `prior_8_weeks` (48 avg units) and another uses `manual_override` (75 and then 95 avg units — the two BLDUP rows are identical IDs with different values). Using either without resolution will materially change expected lift. | Requires business stakeholder decision. Recommend flagging all BLDUP rows; default to the `prior_8_weeks` method until overridden. Do not blend methods. |
| BL-2 | Mixed baseline methods across retailers for the same product | 🟡 Medium | For P1001: R001 uses `prior_8_weeks`, R002 uses `same_period_last_year`, R003 uses `manual_override`, R004 uses `same_period_last_year`. Different methods produce different expected baselines, making cross-retailer lift comparisons non-comparable. | In the lift model, always surface `baseline_method` alongside lift metrics. Recommend a governance rule: standardize method per product tier (e.g., new products use `prior_8_weeks`; established products use `same_period_last_year`). |
| BL-3 | `avg_weekly_units = 'unknown'` (string) for BL00006 | 🔴 Critical | `R002 / P1002` has a literal string `'unknown'` for `avg_weekly_units`. This record will break numeric aggregations and makes R002's P1002 baseline unusable. | Cast to `FLOAT`; treat `'unknown'` as `NULL`. Flag this baseline record as incomplete. Do not impute without source data. |
| BL-4 | `product_key` uses SKU format for some records | 🟡 Medium | Four baseline records (BL00021–BL00024) reference `SKU-BETA-002` instead of `P1002`. This mirrors the issue in POS and campaigns. | Resolve via SKU-to-product_id lookup, same approach as POS-6 and MC-2. |

---

### 8. `promo_calendar_raw`
**Row count:** 5

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| PC-1 | Orphaned `retailer_id = R999` | 🟡 Medium | `PR005` references `R999`, which does not exist in `retailers_raw`. Cannot be joined to any retailer dimension. | Flag as unresolvable. Exclude from lift confound analysis until retailer is identified. |
| PC-2 | `expected_discount_pct = 'N/A'` for PR004 | 🟡 Medium | String value in a numeric field. Cannot be used in discount-adjusted lift calculations. | Cast to `FLOAT`; treat `'N/A'` as `NULL`. |
| PC-3 | `promo_type = 'Unknown'` and `funding_source = 'Unknown'` for PR005 | 🟢 Low | Placeholder values; the promo is also tied to the orphaned retailer. | Flag as incomplete. |

---

### 9. `taxonomy_lookup_raw`
**Row count:** 17

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| TL-1 | Missing coverage for `currency` normalization | 🟡 Medium | The lookup includes platform, funnel_stage, channel, country, product_status, and promo_flag — but not `currency`. The `US Dollars` / `usd` / `USD` inconsistency in `marketing_performance_raw` (MP-2) has no lookup entry. | Add three rows: `US Dollars → USD`, `usd → USD`, `USD → USD`. |
| TL-2 | Missing coverage for `region` normalization | 🟡 Medium | `NA` / `North America` inconsistency is present across four tables but no lookup mapping exists. | Add: `NA → North America` (with note that NA is ambiguous — validate no "not applicable" use cases exist). |
| TL-3 | Missing coverage for `on_hand_status` normalization | 🟡 Medium | No lookup entries for the five variants in POS data. | Add entries for `in_stock`, `In Stock`, `OOS`, `low stock`. |
| TL-4 | Missing coverage for `retailer_tier` normalization | 🟢 Low | `tier1` and `Tier One` have no lookup entries. | Add: `tier1 → Tier 1`, `Tier One → Tier 1`. |
| TL-5 | `funnel_stage: Engagement → Consideration` mapping has confidence 0.75 | 🟢 Low | This is a subjective mapping. Engagement and Consideration are distinct stages in some frameworks. | Apply the mapping but preserve the original value and confidence score in staging. Flag for business stakeholder review. |

---

### 10. `ai_taxonomy_suggestions_raw`
**Row count:** 5

| # | Issue | Severity | Detail | Recommended Treatment |
|---|---|---|---|---|
| AI-1 | 3 of 5 suggestions are unreviewed | 🟡 Medium | AI002 (`complete_payment → purchase`, 0.87), AI003 (`North Star Retail → Northstar Retail`, 0.81), and AI004 (`SPRING-SEARCH-BETA → Spring Launch`, 0.62) are all unreviewed. | Do not apply unreviewed AI suggestions automatically. Surface them in a `stg_ai_taxonomy_suggestions` model with a `is_approved` flag. Require human review before promoting to `taxonomy_lookup_raw`. |
| AI-2 | AI005 was reviewed and rejected | 🟢 Low | `PlatformX → TikTok` was rejected by a reviewer. This is correct governance behavior — the mapping should not be applied. | Confirm `rejected` decisions are excluded from downstream logic. |

---

## Cross-Table Issues

| # | Issue | Severity | Detail |
|---|---|---|---|
| X-1 | Three tables use SKU as a product identifier instead of product_id | 🔴 Critical | `marketing_campaigns_raw` (CAMP006), `retail_pos_weekly_raw` (~1% of rows), and `pos_baseline_history_raw` (4 rows) all reference `SKU-BETA-002` where `P1002` is expected. A join layer must resolve SKU to product_id before any cross-domain model can work. |
| X-2 | `P4040` is referenced in both campaigns and POS but does not exist in products | 🔴 Critical | Cannot be resolved from available data. All records tied to P4040 should be isolated in a quarantine model. |
| X-3 | `retailer_id` case inconsistency is cross-table | 🔴 Critical | `retail_pos_weekly_raw` has mixed case retailer IDs; `pos_baseline_history_raw` and `promo_calendar_raw` use uppercase only. A `UPPER(retailer_id)` normalization must be applied universally in staging before any join. |
| X-4 | No shared date spine / fiscal calendar | 🟡 Medium | POS data is weekly (week_start_date), marketing performance is daily (activity_date), and baseline is a period summary. A date dimension with fiscal week mapping is needed to align these grains for lift calculation. |
| X-5 | OOS weeks will confound lift measurement | 🟡 Medium | 143 POS rows are flagged `OOS`. Lift calculated during OOS weeks understates true demand lift. These rows need to be flagged and optionally excluded or capped in the lift model. |

---

## Recommended dbt Staging Model Checklist

Before building mart-level models, every staging model should address:

- [ ] `stg_products` — dedup P1002, normalize status/SKU/dates, flag bad-date
- [ ] `stg_retailers` — normalize tier/country/region/channel, flag R001/R006 duplicate pending review
- [ ] `stg_campaigns` — normalize platform/region/funnel_stage, resolve SKU product key, flag P4040
- [ ] `stg_marketing_performance` — cast spend to float, normalize currency/attribution_window, flag MPDUP1
- [ ] `stg_funnel_events` — normalize platform, map events to canonical funnel stages, flag FE_BAD
- [ ] `stg_pos_weekly` — normalize retailer_id to UPPER, resolve SKU product key, flag negative units, normalize promo_flag/on_hand_status/country, flag POSDUP1, flag R404
- [ ] `stg_pos_baseline` — cast unknown units to NULL, resolve SKU product key, flag BLDUP conflict
- [ ] `stg_promo_calendar` — flag R999 orphan, cast N/A discount to NULL
- [ ] `stg_taxonomy_lookup` — add missing currency/region/on_hand_status/retailer_tier mappings
- [ ] `stg_ai_taxonomy_suggestions` — add `is_approved` flag; exclude unapproved from auto-application

---

## Key Assumptions (To Confirm Before Build)

1. **R001 vs R006 (Northstar / North Star Retail):** Assumed same retailer pending business confirmation. All lift calculations should be consolidated under R001 once confirmed.
2. **MPDUP1 (duplicate performance row):** Assumed to be an erroneous double-load. Defaulting to MP00013 (the non-duplicate row for the same key).
3. **POSDUP1 (duplicate POS row):** Using the lower value (180 units / $3,598) as a conservative default until source is clarified.
4. **BLDUP (duplicate baseline):** Defaulting to `prior_8_weeks` method until stakeholder confirms the manual override.
5. **Negative units_sold:** Treated as return/adjustment transactions, not data errors. Excluded from lift numerator by default.
6. **P4040:** Treated as unresolvable — quarantined from all join models.
7. **Attribution windows:** Not normalized across platforms for aggregation — different windows are kept separate. Cross-platform ROAS comparisons will note this limitation.
8. **AI taxonomy suggestions:** None applied without explicit human review sign-off, regardless of confidence score.

---

## What This Data Can and Cannot Support

**Can support (with fixes above):**
- Product-level weekly POS performance fact
- Retailer/channel dimension
- Campaign dimension with standardized taxonomy
- Marketing spend and funnel performance by normalized platform and stage
- Lift calculation (actual vs. baseline) for P1001, P1002, P1003, P1005, P1008 at R001–R004
- Promo confound flagging for lift weeks

**Cannot support without additional data:**
- Lift for P4040 or any campaign referencing it
- Cross-platform ROAS on a unified attribution basis (windows differ)
- R006 lift history until R001/R006 dedup is resolved
- Causal lift inference (observational only — no holdout/control group in this dataset)
