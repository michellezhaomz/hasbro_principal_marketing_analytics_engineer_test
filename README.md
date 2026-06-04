# Hasbro Principal Marketing Analytics Engineer Assessment

## Executive Summary

This project delivers a layered dbt architecture connecting Hasbro's marketing activity to retail POS outcomes, enabling defensible marketing lift measurement across campaigns, products, and retail channels.

**What was built:**
- 10 staging models that cleanse and standardize all raw source data
- 3 intermediate models that resolve cross-table identifier and taxonomy problems once, for all downstream consumers
- 4 dimension models (product, retailer, campaign, date)
- 5 fact models covering marketing performance, funnel activity, POS weekly sales, baselines, and marketing lift
- 2 reporting models: a unified effectiveness view and a queryable data quality summary

**What was found in the data:**
- The most significant data quality issues involved cross-system product resolution, attribution window fragmentation, taxonomy inconsistency, and lift measurement confounding from promotions and inventory conditions
- Additional medium-priority issues that could affect metric consistency if left unstandardized
- Preliminary lift signal is detectable for P1001 (Alpha Adventure Set) during CAMP001, but confounded at R001 by an overlapping retail promotion — R003 provides the cleaner measurement signal for the same campaign
- Attribution window fragmentation across 5 variants means any ROAS figure that aggregates across windows overstates performance; the models enforce a single standard window for reporting

**Governance delivered:**
- Taxonomy managed as a version-controlled seed file — every mapping change is auditable via Git
- AI taxonomy suggestions quarantined until human-reviewed; no unreviewed suggestion enters any mart model
- Metric definitions documented in `docs/METRIC_DEFINITIONS.md`

---

## Key Business Findings

The modeled data supports a directional read of marketing effectiveness across campaign performance, funnel activity, POS outcomes, and observed lift. Because the dataset does not include a randomized control group, the findings should be interpreted as observational rather than causal.

**1. Campaign efficiency varied meaningfully by strategy and funnel stage.** CAMP005 and CAMP003 represented the highest spend campaigns, while CAMP006 generated the strongest attributed revenue relative to spend. CAMP006 is classified as a retargeting campaign in the conversion stage of the funnel. Its stronger efficiency is directionally consistent with retargeting behavior, where campaigns reach consumers who may already have demonstrated interest. This should be treated as a performance pattern rather than a causal conclusion.

**2. Product and campaign mapping quality directly affects measurement.** The data uses different product identifiers across sources — product IDs, product keys, and SKUs — creating a join risk between campaign metadata, POS sales, and baseline history. A centralized product resolution layer is necessary before evaluating campaign outcomes. Without it, campaign performance could be disconnected from the correct POS records, resulting in incomplete or misleading lift estimates.

**3. POS lift signals exist, but interpretation depends on promotion and inventory context.** Several campaign-product-retailer combinations show actual POS performance above expected baseline. However, some periods overlap with retail promotions or inventory constraints. When a campaign overlaps with a retailer promotion, observed lift may reflect a combination of marketing impact, promotional pricing, and baseline demand. Cleaner observations are separated from confounded ones using promotion, inventory, and baseline-quality flags.

**4. Attribution methodology is a major reporting risk.** The marketing performance data includes multiple attribution windows. Aggregating across them risks double-counting or overstating performance. The model preserves all raw attribution windows and uses a project-level standard window for aggregated reporting, allowing consistent campaign comparison while retaining source-level detail.

**5. Taxonomy governance is required before this can scale.** Platform names, funnel events, campaign stages, regions, currencies, and inventory statuses all require standardization. The solution is a governed, version-controlled taxonomy layer that any team member can review and update through a standard approval process, rather than embedding business definitions in code where they become invisible to non-engineers.

**6. AI can accelerate classification but should not replace business review.** AI taxonomy suggestions are useful for identifying likely mappings and duplicate entities. However, confidence scores should be treated as prioritization signals, not proof of correctness. Humans remain responsible for approving taxonomy changes, lift methodology assumptions, and business-critical metric definitions.

---

## Design Principles

1. **Preserve raw data.** Staging models flag issues; they do not silently drop or overwrite source records. Every DQ decision is visible and reversible.
2. **Make data quality issues queryable, not just documented.** `mart_data_quality_summary` surfaces all DQ flags in a single model so issues can be monitored over time, not just found once.
3. **Solve cross-table resolution once.** Product key resolution and funnel event mapping live in dedicated intermediate models. No downstream model reimplements these.
4. **Separate business logic from reporting logic.** Facts contain grain-level calculations. Reporting views contain pre-joined, pre-aggregated summaries. BI tools should not need to reimplement business rules.
5. **Surface confidence and limitations alongside metrics.** Every lift row carries a `lift_confidence` classification (`clean`, `confounded`, `incomplete`, `unresolvable`). Analysts always know what they can and cannot trust.

---

## Design Decisions & Tradeoffs

### Product Key Resolution
Product identifiers appear as `product_id`, `product_key`, and SKU across campaigns, POS, and baseline data. I chose to centralize resolution in `int_product_key_resolution` rather than resolving identifiers independently in downstream models. This reduces duplicated logic, improves consistency, and creates one auditable layer for unresolved mappings such as `P4040`.

### Retailer Deduplication
R001 and R006 appear to be a potential retailer duplicate, but the available data does not conclusively prove they represent the same physical retailer. I chose to preserve both records and flag the issue rather than automatically merge them. This protects reporting integrity until business validation is available.

### Funnel Canonicalization
Platform funnel events use different naming conventions across Meta, TikTok, YouTube, and Google. I chose to preserve the raw event names while mapping them into canonical event types and funnel stages in `int_funnel_event_mapping`. This supports cross-platform reporting while keeping source-platform context available for audit.

### Attribution Windows
The marketing performance data contains multiple attribution windows including `1d_click`, `7d_click`, and `view_through_1d`. I chose not to aggregate mixed attribution windows. The reporting layer standardizes to a single window for aggregated performance reporting while preserving the raw attribution window in `fct_marketing_performance`.

### Lift Measurement
The dataset does not contain a holdout group or randomized control design. I chose to present lift as observational rather than causal. `fct_marketing_lift` compares actual POS performance against baseline expectations and surfaces confound flags such as promotion overlap, out-of-stock status, missing baseline data, and unresolved product mappings.

### Data Quality Handling
I chose to surface data quality issues through flags and `mart_data_quality_summary` instead of silently dropping or correcting records. This makes the pipeline more transparent and gives downstream users a way to monitor whether issues are improving or worsening over time.

---

## Modeling Philosophy

Four-layer architecture following the medallion pattern:

```
Raw (SQLite) → Staging → Intermediate → Marts (Dims + Facts) → Reporting
```

| Layer | Purpose | Materialization |
|---|---|---|
| Staging | 1:1 with raw tables. Type casting, taxonomy normalization, DQ flags. No cross-table joins. | Table* |
| Intermediate | Cross-table resolution: product keys, funnel event mapping, date spine. Solved once. | Table* |
| Marts | Dimensional model — reusable business entities and facts at natural grain. | Table |
Reporting | Pre-joined reporting models built for analysts and BI tools. | Table*

*All layers use `table` materialization in this SQLite implementation. In production (Snowflake/BigQuery/Redshift), staging, intermediate, and reporting would be views.

See [`docs/MODEL_DESIGN.md`](docs/MODEL_DESIGN.md) for full model inventory with grain, columns, and design decisions.

---

## Architecture

```
Campaign + Product + Retailer
          ↓
     POS Weekly Sales
          ↓
   vs. Expected Baseline
          ↓
    Observed Lift
   (clean / confounded / incomplete)
```

```
models/
├── staging/           10 models — one per raw table
│   ├── sources.yml
│   ├── staging_models.yml
│   ├── stg_products.sql
│   ├── stg_retailers.sql
│   ├── stg_campaigns.sql
│   ├── stg_marketing_performance.sql
│   ├── stg_funnel_events.sql
│   ├── stg_pos_weekly.sql
│   ├── stg_pos_baseline.sql
│   ├── stg_promo_calendar.sql
│   ├── stg_ai_taxonomy_suggestions.sql
│   └── stg_taxonomy_lookup.sql
├── intermediate/      3 models — cross-table resolution
│   ├── int_product_key_resolution.sql
│   ├── int_funnel_event_mapping.sql
│   └── int_date_spine.sql
├── marts/
│   ├── dimensions/    4 models
│   │   ├── dim_product.sql
│   │   ├── dim_retailer.sql
│   │   ├── dim_campaign.sql
│   │   └── dim_date.sql
│   ├── facts/         5 models
│   │   ├── fct_marketing_performance.sql
│   │   ├── fct_funnel_performance.sql
│   │   ├── fct_pos_weekly.sql
│   │   ├── fct_pos_baseline.sql
│   │   └── fct_marketing_lift.sql
│   └── marts_models.yml
└── reporting/         2 models
    ├── rpt_marketing_effectiveness.sql
    └── mart_data_quality_summary.sql
```

---

## Data Quality Summary

41 issues identified across all 10 raw tables. See [`docs/DATA_QUALITY_FINDINGS.md`](docs/DATA_QUALITY_FINDINGS.md) for the full inventory.

| Severity | Count | Examples |
|---|---|---|
| 🔴 Critical | 14 | Duplicate P1002, negative units with positive sales, retailer_id case inconsistency causing silent join failures, MPDUP1/POSDUP1 duplicate rows with conflicting values |
| 🟡 Medium | 18 | Mixed currency formats, 5 attribution window variants, mixed promo_flag encoding, R001/R006 near-duplicate retailer |
| 🟢 Low | 9 | Cosmetic naming inconsistencies, redundant columns |

---

## Risks & Limitations

- **No experimental control group.** Lift is an observational pre/post comparison, not a causal estimate. Campaign exposure and retail promotions overlap, making clean causal attribution impossible without a holdout design.
- **Attribution windows differ across platforms.** `1d_click`, `7d_click`, and `view_through_1d` are not comparable. Cross-platform ROAS comparisons using mixed windows are misleading. Models enforce a single standard window for aggregated reporting; the full window breakdown remains available in `fct_marketing_performance`.
- **R001/R006 retailer near-duplicate is unresolved.** If they are the same retailer, any lift or sales analysis that doesn't consolidate them understates performance at that retail account. Requires business confirmation before merging.
- **P4040 is unresolvable.** CAMP007 and associated POS records cannot be joined to any product dimension. These records are quarantined and excluded from all lift analysis.
- **Several baseline records have conflicting methodologies.** `fct_pos_baseline` preserves all methods. The preferred method is controlled by `var('default_baseline_method')` and can be overridden without changing model logic.
- **AI taxonomy suggestions AI002, AI003, AI004 are unreviewed.** The TikTok `complete_payment → purchase` mapping (AI002, 0.87 confidence) is applied in `int_funnel_event_mapping` but flagged `requires_human_review = 1`. If this mapping is incorrect, TikTok conversion counts are wrong.

---

## Setup

**Prerequisites**
```bash
pip install dbt-core dbt-sqlite
# or use requirements.txt:
pip install -r requirements.txt
```

**Configure database path**

Copy `profiles.yml.example` to `profiles.yml` and update the paths to point to your local SQLite file:
```bash
cp profiles.yml.example profiles.yml
```

Edit `profiles.yml` and replace the placeholder paths with your actual file path. Also create a `schemas/` folder in the project root for dbt-sqlite to use as its schema directory.

Note: `profiles.yml` is excluded from version control. Each contributor maintains their own local copy.

**Run**
```bash
dbt seed          # load taxonomy_supplement.csv into SQLite
dbt run           # build all models
dbt test          # run all tests
```

**Run a specific layer**
```bash
dbt run --select staging
dbt run --select intermediate
dbt run --select marts
dbt run --select reporting
```

**Note on materialization:** All layers are materialized as `table` rather than `view`. SQLite does not support views that reference objects across schemas. In a production environment (Snowflake, BigQuery, Redshift), staging and intermediate models would be views for efficiency.

---

## Documentation

- [`docs/DATA_QUALITY_FINDINGS.md`](docs/DATA_QUALITY_FINDINGS.md) — Full issue inventory with severity, detail, and recommended treatment
- [`docs/MODEL_DESIGN.md`](docs/MODEL_DESIGN.md) — Model inventory with grain, key columns, and design decisions
- [`docs/METRIC_DEFINITIONS.md`](docs/METRIC_DEFINITIONS.md) — Canonical metric definitions and attribution policy
- [`docs/TAXONOMY_GOVERNANCE.md`](docs/TAXONOMY_GOVERNANCE.md) — Governance framework for taxonomy and metric management
- [`docs/AI_GOVERNANCE.md`](docs/AI_GOVERNANCE.md) — Where AI accelerates workflows and where human review is required
