# 0006. Core schema

- Status: Accepted
- Date: 2026-10-06

## Context

The brief specifies a `Finding` (source, category, severity, route, fingerprint, message, optional metric) and a
`Report` (metadata, findings, per-category scores, overall score), with explicit `toJson` and `fromJson` that
validate input and return failures as values.

Two gaps in that list surfaced while designing it:

1. The fingerprint is a hash of source, rule, route, and target, but `rule` and `target` are not fields. They have
   to be, or the fingerprint cannot be recomputed or explained.
2. Lighthouse-style category scores are a weighted share of passing audits. A list of failures alone cannot produce
   that, because it does not say how many rules were checked and passed.

## Decision

All types are immutable. Enums serialize as the strings shown.

- `Category`: `a11y`, `perf`, `responsiveness`, `memory`, `best-practices`.
- `Severity`: `critical`, `serious`, `moderate`, `minor`, `info`. These are axe's impact levels plus `info`, so the
  most detailed source maps without loss. Each adapter documents its mapping.
- `Source`: `attest`, `lighthouse`, `axe`, `timeline`, `flutter-lighthouse`. Closed, because adapters are in-repo.
- `MetricUnit`: `ms`, `bytes`, `count`, `ratio`, `score`.
- `Metric`: `name`, `value` (double), `unit`.
- `Finding`: `source`, `category`, `severity`, `rule`, `route`, `target` (nullable), `fingerprint`, `message`,
  `metric` (nullable). A finding is a failure: something a human acts on and the baseline tracks.
- `RuleOutcome`: `source`, `category`, `rule`, `route`, `weight`, `passed`. Every rule an adapter saw, passing or
  not, so a category score can be the weighted share that passed.
- `Measurement`: `source`, `category`, `route`, `metric`, and an optional `toolScore` when the tool already scored
  it (Lighthouse does).
- `ReportMetadata`: `app`, `commit` (nullable), `timestamp` (UTC ISO-8601, passed in from `io/`),
  `flighthouseVersion`, `toolVersions` (source to version string).
- `Scores`: a score per category, nullable where the category had no inputs, and `overall`.
- `Report`: `schemaVersion` (starts at 1), `metadata`, `findings`, `scores`, and the inputs that produced the scores
  (`ruleOutcomes`, `measurements`) so a report can be re-scored without the raw files.

Serialization:

- `toJson` returns `Map<String, Object?>` with a fixed key order. Findings are sorted by fingerprint and outcomes by
  `(source, rule, route)`, so two runs over the same inputs produce byte-identical JSON.
- `fromJson(Object? json)` returns `Result<T, SchemaFailure>`. A `SchemaFailure` carries the JSON path
  (`$.findings[3].severity`), what was expected, and what was found. Unknown keys are rejected.
- Hand-written, no code generation.

A category with no inputs scores `null` and renders as "not measured", never as 100.

## Consequences

- `rule`, `target`, `RuleOutcome`, and `Measurement` are additions to the brief.
- `schemaVersion` lets a newer flighthouse read an older baseline or report, or refuse it with a clear message.

## Alternatives considered

- **`json_serializable`.** Rejected: it adds `build_runner`, and generated `fromJson` throws on bad input rather than
  returning a value with a path.
- **Severity-weighted penalty instead of `RuleOutcome`.** Simpler, but not comparable to Lighthouse scores.

## Resolved questions

- The `rule` and `target` fields, `RuleOutcome`, and `Measurement` were approved as additions to the brief's schema
  on 2026-10-06.
