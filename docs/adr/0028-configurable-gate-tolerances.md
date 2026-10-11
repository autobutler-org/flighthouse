# 0028. Every gate tolerance is a config key with today's value as its default

- Status: Accepted
- Date: 2026-10-10

## Context

[ADR 0027](0027-quark-gate-tolerances.md) fixed three things in code after measuring one quark instance: the
Lighthouse throttling the web runner passes, the rule that a new finding carrying a metric does not fail the gate, and,
by leaving them alone, the two score lines the Lighthouse adapter uses to decide what is a finding and how severe it
is. Its Consequences say "Nothing new is configurable."

`gate.minSeverity` and `gate.maxScoreDrop` already come from `flighthouse.yaml`. The other values that decide a verdict
do not, so a project whose variance differs from quark's cannot tune them without a code change.
[#115](https://github.com/autobutler-org/flighthouse/issues/115) asks for them as config keys.

## Decision

Three groups of optional keys. A config that sets none of them produces the same report and verdict as before.

```yaml
web:
  lighthouse:
    throttling:
      rttMs: 40
      throughputKbps: 10240
      cpuSlowdownMultiplier: 1
gate:
  metricFindings: score
scoring:
  lighthouse:
    passingScore: 0.9
    seriousScore: 0.5
```

1. **`web.lighthouse.throttling`** sets the three simulated-throttling values the runner passes to Lighthouse. Each key
   is optional and defaults to the `--preset=desktop` value from ADR 0027. `rttMs` is a number of at least 0,
   `throughputKbps` is greater than 0, and `cpuSlowdownMultiplier` is at least 1. Lighthouse itself only checks that
   each is a number, but its simulator divides by throughput, and Chrome's CPU throttling rate starts at 1. The three
   request-level flags (`requestLatencyMs`, `downloadThroughputKbps`, `uploadThroughputKbps`) stay fixed at 0: they
   apply only to DevTools throttling, which the runner does not use.
2. **`gate.metricFindings`** is `score` or `new`. `score`, the default, is ADR 0027's rule: a new finding that carries
   a metric is reported but only the category score drop gates it. `new` restores ADR 0009's rule for those findings:
   a new one at or above `gate.minSeverity` fails.
3. **`scoring.lighthouse`** sets the two audit score lines. An audit scoring below `passingScore` is a finding and a
   failed rule outcome. A measured audit scoring below `seriousScore` is `serious`, otherwise `moderate`. Both are
   numbers from 0 to 1, and `seriousScore` must not exceed `passingScore`. The key sits under `scoring` because the
   lines interpret Lighthouse's scores and apply to imported Lighthouse reports as well as to web runs.

A bad value is a `ConfigFailure` naming the dotted path, as `gate.maxScoreDrop.perf` is today.

This supersedes one line of ADR 0027, "Nothing new is configurable." The defaults, and every measurement behind them,
stand.

Other constants found while reading the gate, the runner, and the adapters, and what happens to each:

| Constant | Where | Decision |
| --- | --- | --- |
| `_pointTolerance` (1e-9) | `pipeline/gate.dart` | Stays. It absorbs floating-point rounding, not variance. |
| `_weightTolerance` (1e-9) | `config/parse_config.dart` | Stays, for the same reason. |
| Weight bands 10, 7, 3 in `severityForWeight` | Lighthouse adapter | Stays. They invert Lighthouse's own accessibility weights back to axe impacts. |
| Severity weights 10, 7, 3, 1, 0 | attest adapter | Stays. The same mapping in the other direction. |
| `_minAverageScore`, `_maxFailingScore` | `pipeline/log_normal.dart` | Stays. They are the shape of Lighthouse's scoring curve; `scoring.metrics` already sets the control points. |
| Form factor and screen emulation flags | `io/lighthouse_runner.dart` | Stays. ADR 0023 ties them to `web.viewport`. |
| Tested major versions | every adapter | Stays. They state what was tested, not a tolerance. |

## Consequences

- A project can match its own measured variance without a code change, and a quark-specific choice no longer binds
  every other project.
- Reports and baselines taken under different `throttling` or `scoring.lighthouse` values are not comparable. A
  baseline must be regenerated when either changes.
- Lowering `passingScore` changes which binary audits pass, so it changes category scores, not just the finding list.
- `parseLighthouse` takes the score lines as an optional argument, so its public signature grows by one named
  parameter with a default.
- More keys to document and to get wrong. Each has a default and a failure that names it.

## Alternatives considered

- **Throttling through `lighthouse.command` only.** A project can already append `--throttling.*` flags there, but the
  runner appends its own after them, and Lighthouse's flag parsing would then see each flag twice.
- **A boolean `gate.gateMetricFindings`.** Two named modes read better in a config file and leave room for a third
  without a rename.
- **Score lines under `sources.lighthouse`.** That section says where raw output lives and is rejected when `web` is
  configured, so a web run could not set them.
- **Exposing every request-level throttling flag.** Nothing uses DevTools throttling, so those keys would do nothing.
