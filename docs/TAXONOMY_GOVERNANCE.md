# Taxonomy & Metric Governance

## The Problem This Solves

The raw data in this assessment illustrates a common failure mode: taxonomy managed ad hoc across multiple systems simultaneously — a lookup table, an AI suggestion table, source system fields, and analyst memory. At the scale of a real marketing data platform, this produces:

- Silent join failures (retailer_id case inconsistency)
- Incomparable metrics (5 attribution window variants, 3 currency formats)
- Competing definitions ("Engagement" as a funnel stage vs. "Consideration")
- Untraceable decisions (no record of when or why a mapping was added)

The governance framework below treats taxonomy as a managed product, not a one-time cleansing task.

---

## Taxonomy Management

### The Seed File Is the Source of Truth

`seeds/taxonomy_supplement.csv` is the version-controlled extension to `taxonomy_lookup_raw`. All new taxonomy mappings are added here, not directly to the database.

**Workflow for adding a new mapping:**
1. Identify the new raw value requiring normalization (e.g., a new platform name from a new ad source)
2. Add a row to `taxonomy_supplement.csv` with the appropriate `taxonomy_type`, `raw_value`, `canonical_value`, `effective_start_date`, and `confidence_score`
3. Submit a pull request with a brief explanation of why the mapping is correct
4. A second analyst reviews and approves the PR
5. Run `dbt seed && dbt run --select stg_taxonomy_lookup+` to propagate

This makes every taxonomy decision auditable through Git history. "When did we start treating `Meta/Facebook` as `Meta`, and who decided?" becomes a two-second Git log query.

### Quarterly Review Process

Every taxonomy type should be reviewed quarterly:

| Taxonomy Type | Review Trigger |
|---|---|
| `platform` | When a new ad platform is added or an existing platform renames events |
| `funnel_event` | When a platform updates its event taxonomy (TikTok and Meta do this regularly) |
| `channel` | When a new retail channel type is added |
| `country` / `region` | When a new market launches |
| `attribution_window` | When the attribution standard changes (requires stakeholder alignment) |

The `int_funnel_event_mapping` model includes platform/event combinations. Any unmapped event produces `dq_unmapped_event = 1` in `fct_funnel_performance`. Monitoring this flag is the trigger for a quarterly funnel event review.

---

## AI-Assisted Classification

AI taxonomy suggestions (`ai_taxonomy_suggestions_raw`) follow a two-stage workflow:

**Stage 1: AI generates a candidate mapping**
- The AI model produces a suggested canonical value with a confidence score and reasoning
- This row enters `stg_ai_taxonomy_suggestions` with `is_pending_review = 1`
- It does NOT enter any mart model

**Stage 2: Human reviews and decides**
- A qualified analyst reviews the suggestion in context
- `reviewed_flag` is set to `Y`; `reviewer_decision` is set to `accepted` or `rejected`
- Accepted suggestions are promoted to `taxonomy_supplement.csv` via PR (same workflow as above)
- Rejected suggestions are preserved with their rejection status for audit

**Confidence score is a triage tool, not an approval gate.** A 0.94 confidence score (AI001) still required human review before the mapping was applied. A 0.31 confidence score (AI005, PlatformX → TikTok) was correctly rejected. Confidence scores help prioritize which suggestions to review first; they do not authorize automatic application.

---

## Metric Governance

Metric definitions (see `docs/METRIC_DEFINITIONS.md`) are managed as documentation in this repository, not as BI tool calculated fields. This prevents definition drift between tools.

**Ownership model:**
- Analytics Engineering owns: metric formulas, grain definitions, attribution window policy, lift methodology
- Marketing stakeholders own: attribution window standard (which window to use for headline ROAS), baseline method preference, funnel stage definitions for campaign planning
- Neither party changes definitions unilaterally — changes go through a documented review

**Breaking change policy:**
Any change to a metric definition that would change a previously-reported number is a breaking change and requires:
1. A version bump in `dbt_project.yml`
2. An entry in a `CHANGELOG.md` noting what changed and why
3. Stakeholder notification before deployment

---

## At Scale

The approach above is designed to work at the size of this assessment. For a production deployment at Hasbro scale:

1. **`taxonomy_lookup_raw` becomes a managed dimension table** with a proper change-data-capture pipeline, not a static SQLite table. The seed file pattern used here is the equivalent governance model implemented in lightweight form.

2. **Funnel event mapping becomes a configuration table**, not SQL CASE statements. New platforms and new events can be added without a code change.

3. **A data contract is established with each source system owner** (Meta, Google, retail data feeds) documenting which fields are expected, their data types, and acceptable value ranges. dbt source freshness and schema tests enforce this contract automatically.

4. **The DQ summary model (`mart_data_quality_summary`) feeds an alerting pipeline** — a Slack notification when any DQ flag count increases week-over-week signals a source system change before it propagates to reporting.
