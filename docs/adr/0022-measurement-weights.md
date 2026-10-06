# 0022. Measurements carry a weight

- Status: Accepted (by the maintainer, 2026-10-06)
- Date: 2026-10-06
- Amends: [ADR 0006](0006-core-schema.md), [ADR 0008](0008-scoring.md)

## Context

ADR 0008 defines a category score as the weighted mean of its metric scores and rule scores. ADR 0006 gave
`RuleOutcome` a weight but not `Measurement`, so there was no faithful way to combine the two. Lighthouse computes a
category score as `sum(weight * score) / sum(weight)` over every audit in the category, binary and metric alike, with
the weights listed per audit in the LHR's `categories.*.auditRefs`.

## Decision

- `Measurement` gains `weight`: a number of at least 0, on the same scale as `RuleOutcome.weight`.
- A category score is `sum(weight * score) / sum(weight)` over the category's rule outcomes (score 1 if passed, 0
  if not) and its scorable measurements. A measurement is scorable when it has a `toolScore` or configured control
  points. Items with weight 0 are reported but don't count. A category whose counted weight sums to 0 is not
  measured (`null`).
- The Lighthouse adapter copies each audit's weight from the LHR, so a Lighthouse category recomputed by flighthouse
  matches Lighthouse's own score. Other adapters set weights per their own ADR or config.
- The schema stays at version 1. Nothing has been released, so there are no v1 files to migrate.

## Alternatives considered

- **Each measurement counts with weight 1.** No schema change, but a recomputed Lighthouse perf score would no
  longer match Lighthouse, which weights its metrics unequally.
- **Use LHR category scores directly.** It matches Lighthouse, but other sources would still need a weighting rule,
  and the score would lose its per-audit breakdown.
