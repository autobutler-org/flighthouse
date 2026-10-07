# Phase 1 summary

Epic #1. Written 2026-10-07 at `main` after #57.

## What works

`flighthouse collect`, `report`, `ci`, and `baseline [--update]` run end to end on **attest** and **Lighthouse**
output, and produce one scored `report.json` and a self-contained `report.html`. The CI gate fails only on new
findings or on score drops past configured thresholds.

| Area | Where | Evidence |
| --- | --- | --- |
| Packaging, CI | #37, #56 | CI on every PR in the Node-free `dart:stable` image: format, strict analysis, 406 tests, the CLI on recorded fixtures, pana at 160/160, `dart pub publish --dry-run` with 0 warnings |
| Failure as values | #38 | sealed `Result` and `Failure`; no throwing in the core |
| Schema | #39, #42 | validating JSON codecs that name the JSON path; canonical, byte-stable encoding |
| Fingerprints, routes | #40, #51 | SHA-256 checked against Python's `hashlib`; normalization proven idempotent over 2000 random routes |
| Config | #41 | `flighthouse.yaml` errors name the key, line, and column |
| Scoring | #43 | Lighthouse's `getLogNormalScore` ported exactly, passing all of Lighthouse's own test vectors |
| Baseline and gate | #45, #46 | new, fixed, and persisting findings; drop thresholds; refuses a baseline from another fingerprint scheme |
| Renderers | #49 | accessible single-file HTML, checked in light, dark, and phone-width screenshots |
| Lighthouse adapter | #50 | re-scoring its output reproduces Lighthouse's category scores exactly (to Lighthouse's 2-decimal rounding) on two real reports |
| attest adapter | #57 | real attest_flutter 1.5.0 output; hand-computed accessibility scores match |
| CLI | #52 | 21 tests over real temporary workspaces, covering every exit code |
| End to end | #53, #57 | attest and Lighthouse merged into one report, compared byte for byte with goldens |
| Real quark report | #14 | release build of quark `main` @ `78c7912`: overall 80, a11y 100, perf 60, best practices 81 |

## What was assumed

Each is written down where it lives. Changing one is a small, local edit.

- **Measurement weights** (ADR 0022, your call). A category score is one weighted mean over rules and metrics,
  Lighthouse's formula.
- **Configuration refinements** (ADR 0021, accepted by me and flagged for your review):
  - validation walks the YAML node tree, to keep line numbers
  - partial `weights` set every unlisted category to 0
  - default metric control points wait until phase 3
- **Severity mappings.**
  - Lighthouse: audit weight 10, 7, 3, 1, 0 maps to critical, serious, moderate, minor, info, inverting
    Lighthouse's own accessibility table. Failing metrics are serious below 0.5, moderate up to 0.9.
  - attest: `error`, `warning`, `info` map to serious, moderate, info.
- **attest passes are inferred.** attest reports only failures, so each of its 15 standard rules with no finding
  counts as passed. A rule disabled in attest's `RuleConfig` therefore counts as passed.
- **Lighthouse route** is `requestedUrl`, not the final URL. quark redirects client-side.
- **Lighthouse categories** other than performance, accessibility, and best practices are ignored (`seo`,
  `agentic-browsing`).
- **Targets are kept as reported** for every source until phase 2 shows what is volatile in Flutter web output
  (ADR 0007).
- **Category scores pool every route and screen.** There are no per-route scores yet.
- **Gate defaults:** fail on new findings at `minor` and above; allowed drops are 2 points (perf 5, overall 2). The
  quark release build scored perf 60 on six of six runs, so 5 points looks safe for a single run there, but that is
  one screen, not a variance study.

## What could not be verified

- **Publishing.** It needs your pub.dev account: #55, assigned to you. Everything up to `dart pub publish` is
  checked in CI.
- **attest on quark** (the open half of #14). Getting attest reports from quark means adding `attest_flutter` to
  quark's tests, a change to quark that waits on your decision. The adapter is proven on a scratch app instead.
- **Distinct quark pages.** With no backend, every public route redirects to `/terms`, so the quark report
  measures one screen six times. Authenticated and distinct pages need the phase 2 runner and a running backend.
- **The real accessibility signal on Flutter web.** a11y 100 on quark is not a pass: most Lighthouse accessibility
  audits don't apply to a default canvas build. #18 measures a semantics-enabled build.
- **macOS and Windows.** CI runs Linux only. The core is pure Dart and `io/` uses `package:path`, but nothing has
  run on the other two.
- **Publishing from a workspace root** (ADR 0003). There is no workspace until #30.
- **pub.dev's own score.** pana is run locally and in CI with the same version pub.dev uses as of today. The
  server can apply additional checks at upload.

## Learned on the way

- quark's Makefile builds web in **debug** by default. A debug build gave 27 MB of JavaScript and perf from 36 to 60
  on one screen; the release build is 8.7 MB and steady. Audits must use release builds.
- Lighthouse 13 has new categories (`agentic-browsing`), and `details.items` isn't always a list.
- attest emits negative hex fingerprints (a 64-bit overflow in its FNV hash), likely worth reporting upstream.

## Open decisions

1. attest on quark: add `attest_flutter` to quark's tests, or leave attest on quark for later?
2. For the phase 2 runner: start a quark backend itself, or assume one is running?
3. Review ADR 0021.
