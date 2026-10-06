# 0008. Scoring

- Status: Accepted
- Date: 2026-10-06

## Context

The brief asks for Lighthouse's log-normal curve for metric values, so scores are comparable across runs, and for
configurable category weights with sensible defaults.

Lighthouse's implementation is `getLogNormalScore({median, p10}, value)` in `shared/statistics.js` of
GoogleChrome/lighthouse (read from `main` on 2026-10-06). It:

- requires `0 < p10 < median`, and returns 1 for `value <= 0`;
- computes `standardizedX = ln(value / median) * 0.9061938024368232 / -ln(p10 / median)`, where the constant is
  `erfc^-1(1/5)`;
- returns `(1 - erf(standardizedX)) / 2`, using an Abramowitz-Stegun style polynomial for `erf`;
- clamps by band: `value <= p10` into `[0.9, 1]`, `value <= median` into `[0.5, 0.9)`, and above the median into
  `[0, 0.5)`, using exact double constants for the band edges.

Lighthouse is Apache-2.0.

## Decision

- **Metric scores.** Port `getLogNormalScore` and its `erf` exactly, constants included, as a pure Dart function. Its
  tests include Lighthouse's own test vectors from `shared/test/statistics-test.js`. Credit Lighthouse in `NOTICE`
  and the README.
- **Bad control points** (`p10 >= median`, non-positive) are a `ConfigFailure` at config parse time, not an exception
  at scoring time.
- **Tool-scored measurements.** When the source already scored a metric (a Lighthouse audit's `score`), use that
  score. Do not re-derive Lighthouse's own scores from its raw values.
- **Rule scores.** A category's rule-based score is the weighted share of `RuleOutcome`s that passed. Weights default
  by severity: critical 10, serious 7, moderate 3, minor 1, info 0. These follow Lighthouse's accessibility audit
  weighting, to be confirmed against its `default-config.js` during implementation.
- **Category score.** The weighted mean of that category's metric scores and rule scores. A category with no inputs
  is `null`.
- **Overall score.** The weighted mean of the non-null category scores, with the weights renormalized over the
  categories that were measured. The report lists which categories were left out.
- **Default category weights:** a11y 0.30, perf 0.30, responsiveness 0.20, memory 0.10, best-practices 0.10.
  Overridable in config. They must sum to 1, or config parsing fails.
- **Default metric control points** ship only for metrics with a known budget. For frame build and raster time at
  60 Hz the budget is 16.7 ms, so the initial points are p10 = 8 ms and median = 16 ms. They are provisional until
  tuned against quark in phase 3. Memory metrics have no default; a memory metric with no configured control
  points is reported but not scored, and the report says so.
- Scores are doubles in `[0, 1]` internally and rounded to a 0 to 100 integer only when rendered.

## Consequences

- Lighthouse and flighthouse agree on any metric both score.
- Renormalizing over measured categories means adding a collector can lower the overall score. The report shows
  which categories contributed, so that is visible.

## Open questions

- Are the default category weights right for quark? They are a starting point, not a measurement.
