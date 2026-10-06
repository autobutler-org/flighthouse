# 0002. Aggregate existing tools, do not reimplement them

- Status: Accepted
- Date: 2026-10-06

## Context

Every audit flighthouse reports on already has a maintained tool. Versions below were read from the pub.dev API
on 2026-10-06.

| Tool                                    | Covers                                                      | Latest            |
| --------------------------------------- | ----------------------------------------------------------- | ----------------- |
| `attest_flutter`, `attest_cli`          | a11y widget-test audits, JSON reports, baseline-diff gate   | 1.5.0, 1.6.0      |
| `flutter_a11y_lens`                     | live a11y audit and headless tests                          | 0.0.1             |
| `flutter_lighthouse`                    | in-app route walking and perf scoring                       | 0.1.0             |
| Lighthouse, Lighthouse CI, axe-core     | web builds                                                  | Node tools        |
| `integration_test` `TimelineSummary`    | frame timing                                                | ships with Flutter|

None of them produces one scored report across categories, and none diffs across tools against one baseline.

## Decision

flighthouse is a thin layer. It ingests these tools' outputs, normalizes them to one schema, dedupes, diffs against
a baseline, scores, and renders. It does not audit a widget tree, measure a frame, or evaluate a WCAG rule itself.

The one new capability is the Flutter web runner ([ADR 0016](0016-semantics-enabled-web-builds.md)): build with
semantics enabled, serve the build, and drive Lighthouse and axe against it.

## Consequences

- Each tool is integrated by an adapter ([ADR 0013](0013-adapter-contract.md)), the only tool-specific code.
- Our correctness depends on their output formats. Fixtures are recorded from the real tools and pinned per tool
  version, so a format change breaks a test rather than a user's CI.
- `flutter_a11y_lens` is at 0.0.1. It is not in the adapter list, and gets one only if demand appears and its
  output format is documented.
