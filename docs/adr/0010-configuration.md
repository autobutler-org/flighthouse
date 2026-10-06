# 0010. Configuration file

- Status: Accepted
- Date: 2026-10-06

## Context

Configuration comes from a file in the repo, YAML or JSON, parsed into an immutable config value. Dart projects
already keep YAML config (`pubspec.yaml`, `analysis_options.yaml`).

## Decision

- `flighthouse.yaml` at the repository root by default, overridable with `--config`. YAML is a superset of JSON, so a
  JSON file goes through the same parser and is accepted under any name passed to `--config`.
- Parsed with `package:yaml`, converted to plain Dart values, then validated into an immutable `Config` by a pure
  function returning `Result<Config, ConfigFailure>`. A failure names the key path and the line and column from the
  YAML span.
- Unknown keys are errors, so a typo fails loudly instead of being silently ignored.
- Every field has a default except `app`.

Initial shape:

```yaml
app: quark
reportDir: .flighthouse
baseline: flighthouse-baseline.json
sources:
  attest:
    dir: build/attest
  lighthouse:
    dir: .flighthouse/raw/lighthouse
routes:
  patterns:
    - /files/:path(.*)
scoring:
  weights: {a11y: 0.3, perf: 0.3, responsiveness: 0.2, memory: 0.1, best-practices: 0.1}
  metrics:
    frame_build_time_p90: {p10: 8, median: 16}
gate:
  minSeverity: minor
  maxScoreDrop: {overall: 2, perf: 5}
```

The `web:` section (build command, serve port, route list, auth) is added in phase 2 by its own ADR.

## Consequences

- Sources point at directories, not globs, so there is no glob dependency. Each adapter reads the `*.json` files in
  its directory.
