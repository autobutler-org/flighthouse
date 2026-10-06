# 0021. Configuration refinements found while implementing

- Status: Accepted (by the implementer under the maintainer's standing go-ahead; flagged for review in PR)
- Date: 2026-10-06

## Context

Implementing [ADR 0010](0010-configuration.md) (#6) turned up three points where ADRs 0008 and 0010 were either
silent or could not be followed as written.

## Decision

- **Validate over YAML nodes, not plain values.** ADR 0010 says to convert the YAML to plain Dart values and then
  validate. Plain values drop source spans, which ADR 0010 also requires for error line and column. The parser
  walks `package:yaml`'s node tree directly instead. Behavior is otherwise as ADR 0010 describes.
- **Partial weights.** When `scoring.weights` is given, it replaces the defaults entirely, and a category not
  listed has weight 0. The listed weights must still sum to 1. Merging a partial list with the defaults would
  almost never sum to 1, and would make the effective weights hard to see from the file.
- **No default metric control points yet.** ADR 0008 promised defaults for frame build and raster time. Their
  metric names come from the `TimelineSummary` adapter (#32), and guessing them now would ship defaults keyed on
  names that may not exist. Defaults land with #32 and #33. Until then a metric without configured control points
  is reported but not scored, as ADR 0008 already says for memory.
- **Empty sections are absent.** `routes:` with no value means the defaults, not an error.

## Consequences

- ADR 0008's default control points are deferred to phase 3, not dropped.
