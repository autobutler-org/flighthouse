# 0027. Gate tolerances for quark, and what the gate must stop doing first

- Status: Accepted; "Nothing new is configurable" superseded by ADR 0028
- Date: 2026-10-09

## Context

[ADR 0009](0009-baseline-and-ci-gate.md) set the default score allowances: overall 2, perf 5, and 2 for every other
category. It left open whether those are right, because "Perf's 5 points is a guess at Lighthouse variance until we
measure quark." [#100](https://github.com/autobutler-org/flighthouse/issues/100) measured it.
[`quark-variance.md`](../evidence/quark-variance.md) has the recipe and findings, and
[`quark-variance.json`](../evidence/quark-variance.json) has the data.

The measurement covers only the quark instance at `http://odroid.lan:8080` on 2026-10-09: frontend 0.49.1, with an
unknown backend commit and the owner's account. It is not quark `d8d2618e`. The routes were `/files`, `/photos`, and
`/settings/general`. There were 15 serial runs with the runner's current Lighthouse settings and 12 with
`--preset=desktop`. The machine was shared and its load was not controlled.

What was measured:

- **axe and accessibility do not vary.** The raw axe results and all 117 axe fingerprints were identical in all 27
  runs. The combined a11y score was 86.62 and best practices 61.54 in every run.
- **Performance is bimodal under the current settings.** The runner sets `--form-factor=desktop` but no throttling,
  so Lighthouse simulates mobile throttling (150 ms RTT, 1.6 Mbps, 4× CPU). In 39 of 45 route runs, performance was
  54 to 59. In the other 6 it was exactly 35, with simulated LCP of 7.85 to 8.04 s, while observed LCP was 102 to
  460 ms. Combined perf ranged 23.94 points and overall 10.26. Excluding that mode, the largest drop between two
  runs was 2.72 points of perf and 1.16 of overall.
- **LCP sits on a scoring boundary.** Lighthouse gives LCP 0.9 at 1200 ms, and the adapter emits a finding below 0.9.
  Normal-mode LCP was 888 to 1599 ms, so the `largest-contentful-paint` finding came and went. Every new finding that
  failed the gate, in every replay, was this one.
- **Default gate verdicts.** `ci` failed 5 of 15 runs against run 01, and 109 of 210 ordered single-run pairs. A
  replayed median of 5 Lighthouse runs per route failed 0, 84, or 246 of 252 sets, depending on which runs formed
  the baseline. All of those failures were new LCP findings or the 35-point mode.
- **`--preset=desktop` (40 ms RTT, 10 Mbps, 1× CPU).** The 35-point mode did not appear. The largest pairwise drop
  over 132 pairs was 2.85 points of perf and 1.22 of overall. LCP was 239 to 272 ms in 32 of 36 route runs and 1373
  to 1430 ms in 4, with observed LCP of 66 to 101 ms in those 4. Those 4 runs still failed 31 of 132 pairs on a new
  moderate LCP finding. Scoring the same pairs alone failed 0. These runs came later and under lower load, so this is
  not a controlled comparison.

## Decision

1. **Tolerances for quark** are the existing defaults, now backed by measurement: `minSeverity: minor`, and
   `maxScoreDrop` overall 2, perf 5, a11y 2, and best practices 2. They cover the largest measured same-mode drops
   (perf 2.85, overall 1.22, a11y and best practices 0) with margin. Quark's config needs no `gate` section.
2. **No tolerance is raised to absorb the 35-point mode.** Covering it would take perf above 24 and overall above
   10.3, which would pass a build that lost a route's LCP entirely.
3. **These tolerances do not give one verdict by themselves.** The gate becomes predictable on quark only with two
   changes, tracked in [#113](https://github.com/autobutler-org/flighthouse/issues/113):
   - The web runner passes Lighthouse throttling that matches its desktop form factor, the values `--preset=desktop`
     uses. This adds to [ADR 0023](0023-web-runner-configuration.md), which already requires desktop form factor
     and matching screen emulation but says nothing about throttling.
   - Lighthouse findings from measured metric audits, the ones that carry a `metric`, stay in the report and the
     baseline but do not count as new findings in the gate. The category score drop already gates them. If this ADR
     is accepted, this rule supersedes ADR 0009's "a `new` finding at or above `gate.minSeverity` fails" for those
     findings only. Binary audits and every axe and attest finding keep failing the gate when new.
4. Until #113 lands and ten consecutive live `ci` runs give one verdict, quark's CI should not gate on flighthouse
   performance. #102 depends on this.

## Consequences

- Score allowances stay one set of numbers across projects. Nothing new is configurable.
- A metric regression such as a slower LCP fails the gate through the perf score. A metric that crosses the 0.9 line
  without moving the score past 5 points no longer fails on its own.
- Performance numbers taken with desktop throttling are not comparable to the phase-2 report or to these default runs.
  Baselines must be regenerated when #113 lands.
- Overall's margin is the smallest: 0.78 points above the largest measured drop. It needs watching in #113's
  re-measurement.

## Alternatives considered

- **Median of N Lighthouse runs per route.** Lighthouse documents this for variance. In replay, a median of 5 removed
  the 35-point mode for most sets, but 21 of 756 sets still failed on score, and up to 246 of 252 failed on the LCP
  finding, depending on the baseline. It also multiplies Lighthouse time per route by N. If #113's re-measurement
  still varies, measure this next.
- **Larger tolerances** (perf 8, overall 3): single-run pairs still failed 35 of 210 on score alone, and the LCP
  finding still failed regardless.
- **`gate.minSeverity: serious`**: this would hide the moderate LCP finding, but also every new moderate axe finding.
  Quark has 19 stable moderate axe findings now, such as `region`.
- **Passing `--preset=desktop` through quark's `lighthouse.command`**: this works today without code, as the variant
  runs show. But the runner's form factor and throttling would still disagree for every other project.

## Open questions

- The cause of the bimodal simulated LCP is unknown. The runs could not separate machine load, the instance, and
  Lighthouse's simulation.
- These results come from one instance with an unknown backend commit. Quark's own CI will run a different build, data
  set, and machine, so #102 needs its own baseline.
