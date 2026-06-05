# Metric Definitions

This document defines all canonical metrics used in this project. It is the contract between analytics engineering and marketing stakeholders. BI tool calculated fields should reference these definitions, not reimplement them.

---

## Marketing Performance Metrics

| Metric | Definition | Formula | Notes |
|---|---|---|---|
| **Spend** | Total paid media cost | `spend` | NULL when source reports N/A |
| **Impressions** | Total ad impressions served | `impressions` | Platform-specific definitions vary; see platform notes |
| **Clicks** | Total clicks on ad | `clicks` | Includes all click types unless link_clicks is specified |
| **Link Clicks** | Clicks to destination URL | `link_clicks` | Meta/Instagram only; NULL for other platforms |
| **Video Views** | Video view count | `video_views` | Definition varies by platform (see below) |
| **Conversions** | Platform-reported conversion events | `conversions` | Attribution-window dependent; always report with window |
| **Revenue Attributed** | Platform-reported attributed revenue | `revenue_attributed` | Attribution-window dependent |
| **CPM** | Cost per 1,000 impressions | `spend / impressions * 1000` | |
| **CPC** | Cost per click | `spend / clicks` | |
| **CTR** | Click-through rate | `clicks / impressions` | |
| **CVR** | Conversion rate | `conversions / clicks` | |
| **ROAS** | Return on ad spend | `revenue_attributed / spend` | **Always filter to a single attribution window** |

### Treatment of Baseline Values

Baseline values (`avg_weekly_units`, `avg_weekly_sales`) are treated as pre-computed business inputs rather than recalculated from raw transaction data. The source data provides the result of each baseline calculation alongside the method used, but does not include the underlying calculation logic or the historical transaction window that produced it.

This means:
- The lift model consumes baseline values as-is without attempting to verify or recreate them
- Different methods (`prior_8_weeks`, `prior_12_weeks`, `same_period_last_year`, `manual_override`) may produce different expected values for the same retailer/product
- The `baseline_method` column is always surfaced alongside lift metrics so analysts know which method was used
- Cross-retailer lift comparisons should account for the fact that different retailers may use different baseline methods

### Attribution Window Policy

**Standard reporting window: `7d_click`**

Defined in `dbt_project.yml` as `var('standard_attribution_window')`. Use `is_standard_attribution_window = 1` in `fct_marketing_performance` for any aggregated ROAS reporting.

Available windows in the data:
- `1d_click` — conversion within 1 day of click
- `7d_click` — conversion within 7 days of click (standard)
- `view_through_1d` — conversion within 1 day of view (no click required)
- `platform_default` — platform-defined window; definition unknown

**Do not aggregate across windows.** `1d_click` + `7d_click` for the same campaign/date counts the same conversions twice.

### Platform-Specific Notes

| Platform | Impression Definition | Video View Definition |
|---|---|---|
| Meta | Ad served in-feed | 3 seconds or more |
| Instagram | Ad served in-feed | 3 seconds or more |
| Google | Ad shown on SERP | N/A (search) |
| YouTube | Ad shown before/during video | 30 seconds or complete view |
| TikTok | Ad shown in feed | 2 seconds or more |

---

## Funnel Metrics

| Canonical Stage | Definition | Included Event Types |
|---|---|---|
| **Awareness** | Ad was served or viewed | impression, video_view |
| **Consideration** | User engaged beyond impression | click, page_view, engaged_view |
| **Conversion** | User completed a purchase action | purchase |

Platform event name mappings are maintained in `int_funnel_event_mapping`. See that model for the full mapping table. Any new platform events must be added there before they flow into `fct_funnel_performance`.

---

## POS Metrics

| Metric | Definition | Notes |
|---|---|---|
| **Units Sold** | Retail units sold in the week | Negative values = returns/adjustments. Exclude `is_return_adjustment = 1` for demand analysis. |
| **Gross Sales** | Retail gross sales dollars | At regular or promo price depending on week |
| **Average Selling Price** | `gross_sales / units_sold` | Derived; not stored |

---

## Lift Metrics

| Metric | Definition | Formula |
|---|---|---|
| **Expected Units** | Baseline units adjusted for seasonality | `avg_weekly_units × seasonality_index` |
| **Expected Sales** | Baseline sales adjusted for seasonality | `avg_weekly_sales × seasonality_index` |
| **Absolute Unit Lift** | Incremental units above expected | `actual_units − expected_units` |
| **Percent Unit Lift** | Lift as a proportion of expected | `(actual_units − expected_units) / expected_units` |
| **Absolute Sales Lift** | Incremental sales above expected | `actual_sales − expected_sales` |
| **Percent Sales Lift** | Lift as a proportion of expected sales | `(actual_sales − expected_sales) / expected_sales` |


### Lift Confidence Classification

Every row in `fct_marketing_lift` carries a `lift_confidence` field:

| Value | Meaning | When to Use |
|---|---|---|
| `clean` | No active promo, not OOS, baseline exists, no DQ flags | Primary lift reporting |
| `confounded` | Active retail promo OR OOS during the measurement week | Report separately; do not blend with clean |
| `incomplete` | Baseline missing or has DQ issues | Exclude from lift reporting |
| `unresolvable` | Product key or retailer key cannot be resolved | Exclude from all analysis |

**Always filter to `lift_confidence = 'clean'` for any headline lift figure.** Report confounded weeks separately as a sensitivity range if needed.

### Platform-Attributed Revenue vs POS Lift

These are two different measurements and should not be conflated:
- `revenue_attributed` in `fct_marketing_performance` is what the ad platform claims it influenced, based on click/view attribution windows. It is self-reported by the platform and subject to attribution window methodology.
- `absolute_sales_lift` in `fct_marketing_lift` is the observed difference between actual retail POS sales and expected baseline sales. It is independent of platform reporting and reflects real units moving off shelves.

A campaign can show strong platform-attributed revenue but weak POS lift (if the attributed conversions were people who would have bought anyway), or strong POS lift with modest platform-attributed revenue (if the campaign drove in-store sales not captured by digital tracking).

### Baseline Method Policy

Default method: `prior_8_weeks` (set in `dbt_project.yml` `vars.default_baseline_method`).

Available methods in the data:
- `prior_8_weeks` — 8-week pre-campaign average
- `prior_12_weeks` — 12-week pre-campaign average
- `same_period_last_year` — same calendar period, prior year
- `manual_override` — manually provided by commercial team

When multiple methods exist for the same retailer/product, `fct_pos_baseline` preserves all of them. The lift model selects the preferred method first, then falls back to any available clean baseline. The method used is always surfaced as `baseline_method` in the lift fact.
