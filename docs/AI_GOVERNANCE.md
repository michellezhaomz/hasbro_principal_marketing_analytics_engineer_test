# AI-Assisted Workflows: Opportunities and Guardrails

## Summary

| Use Case | AI Role | Human Approval Required | Risk if Wrong |
|---|---|---|---|
| Taxonomy normalization (platform names, event names, retailer spelling variants) | High value — fuzzy matching and semantic similarity at scale | Yes — all suggestions reviewed before production | Incorrect canonical values cascade into every downstream metric |
| Anomaly detection in POS data (negative units, impossible sales spikes, sudden retailer dropouts) | High value — detects outliers faster than manual review | Yes — AI flags, human determines root cause | Could mask legitimate events (promotions, sellouts) or genuine data errors |
| Duplicate entity detection (R001 vs R006, P1002 variants) | Useful for surfacing candidates | Yes — entity resolution requires business context | Incorrect merges produce permanently wrong historical analysis |
| Funnel event canonicalization (new platform event vocabulary) | Medium value — can propose mappings for new events | Yes — incorrect mapping breaks all downstream funnel metrics | |
| Generating dbt model documentation and column descriptions | High value, low risk | Spot-check recommended | Minor — documentation quality issue, not a data integrity issue |
| Lift calculation or baseline method selection | Low value — requires causal reasoning and business context | Yes — fully human decision | Incorrect lift claims mislead marketing investment decisions |
| Attribution window standardization | Low value — business policy decision | Yes — marketing leadership must own the standard | |

---

## Where AI Accelerates This Project

**Taxonomy classification** is the highest-value AI use case in this dataset. The raw data contains dozens of inconsistent string values across platforms, retailers, countries, regions, and event names. Manually maintaining `taxonomy_supplement.csv` is tractable for a dataset this size but becomes expensive at scale. An LLM-powered classifier that ingests new raw values, generates candidate mappings with reasoning, and queues them for human review would reduce taxonomy maintenance cost by 80%+ while keeping humans in the approval loop.

**Anomaly detection** on POS data (flagging weeks where units_sold is implausibly negative, where a retailer suddenly goes dark, or where gross_sales and units diverge) is a pattern-matching task well-suited to ML. The 10 negative-unit rows in this dataset were caught by a simple sign check. At scale — thousands of retailers, hundreds of products, 52 weeks of weekly data — rule-based checks miss edge cases that statistical anomaly detection would surface.

**Documentation generation** from model SQL is already practical. dbt model descriptions, column descriptions, and README sections can be drafted by an LLM and reviewed by the engineer. This project's documentation was produced this way.

---

## Where Human Review Is Non-Negotiable

**Lift methodology decisions.** Choosing a baseline method (`prior_8_weeks` vs. `same_period_last_year`), deciding how to treat OOS weeks in lift calculations, and determining whether a confounded week should be included or excluded in headline reporting are judgment calls that require understanding of the business context. An LLM does not know that the Spring promo at R001 was a strategic retailer investment, not noise — a human who has been in the business meeting does.

**Attribution window standards.** The choice of which attribution window to use for headline ROAS is a marketing philosophy decision. Different teams will defend different answers. This must be owned by marketing leadership and documented explicitly; it cannot be inferred from the data.

**Entity resolution with business impact.** The R001/R006 near-duplicate question is not answerable from the data alone. A human who knows Hasbro's retail account structure knows in five seconds whether Northstar Retail and North Star Retail are the same account. Merging them incorrectly produces wrong historical lift and wrong retail performance comparisons. AI can surface the candidate; only a human can confirm it.

**Reviewing rejected AI suggestions.** AI005 (PlatformX → TikTok, 0.31 confidence) was correctly rejected by a reviewer. The low confidence score was a useful signal, but the decision required knowing what PlatformX actually is in Hasbro's media history — context the model doesn't have.

---

## Applied in This Project

The `stg_ai_taxonomy_suggestions` model enforces the governance boundary in code:

```sql
-- is_approved = 1 only when reviewed AND accepted
case
    when reviewed_flag = 'Y'
     and lower(reviewer_decision) = 'accepted' then 1
    else 0
end as is_approved
```

No unreviewed suggestion enters any staging, intermediate, or mart model. The one accepted suggestion (AI001: `Meta/Facebook → Meta`) flows into `stg_taxonomy_lookup` through the standard taxonomy lookup path, not through a special AI bypass. The mechanism for applying an AI-suggested mapping is identical to applying a manually-created mapping — which means the governance process is the same regardless of how the mapping was generated.
