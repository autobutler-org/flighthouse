# Changelog

## 0.2.0

Adds the Flutter web runner and the axe adapter.

- Breaking: fingerprints move to scheme v2. `ci` refuses a baseline written by 0.1.0; run
  `flighthouse baseline --update` once to regenerate it.
- Flutter web runner: with a `web:` section in `flighthouse.yaml`, `collect` builds the app with semantics
  enabled, serves the build, signs in if configured, and runs Lighthouse and axe-core against each route, writing
  raw output under `<reportDir>/raw/lighthouse/` and `<reportDir>/raw/axe/`. Chrome and axe-core are downloaded
  once into `~/.cache/flighthouse`.
- axe-core 4.11 adapter: violations and incomplete results become findings, and passes and inapplicable rules
  become rule outcomes.
- Sign-in steps can read a `url`, `username`, or `password` from a gitignored `.flighthouse/hosts.yaml` with
  `valueFromHost`, and `collect --host` selects the entry.
- The web runner passes Lighthouse's desktop throttling, so desktop runs are no longer scored under mobile
  throttling.
- A new finding that carries a metric no longer fails the gate by itself; the category score drop gates it.
- Gate tolerances are configurable: Lighthouse throttling, whether a new metric finding fails the gate, and the
  Lighthouse audit score lines. Every key is optional and defaults to the previous behavior.
- A missing Lighthouse, Flutter, or Chrome dependency fails `collect` with exit 3 and a message naming what to
  install, and a Chrome renderer crash is reported as such, naming the route.
- First-run errors say what to do next: a missing `flighthouse.yaml` names its absolute path, a Lighthouse that
  cannot find `node` is reported as a missing Node.js 22, and a failed process shows the first and last lines of
  its standard error.
- Each `ci` failure prints on one line with its rule, route, selector, and message, and a failed gate points at
  `report.html` and `flighthouse baseline --update`.
- `report.html` explains the score scale, color bands, and what each category covers, defines new, fixed, and
  unchanged findings, splits each finding into a headline and a detail block, and shows measurements in readable
  units.
- A [Flutter web quickstart](https://github.com/autobutler-org/flighthouse/blob/main/docs/quickstart-web.md).

## 0.1.0

First release. Reads attest and Lighthouse reports; other sources are in progress.

- `flighthouse collect`, `report`, `ci`, and `baseline [--update]`, with exit codes 0 passed, 1 gate failed,
  2 usage or config error, 3 unusable input.
- One unified, validated report schema (`report.json`), and a self-contained, accessible `report.html` with
  Lighthouse-style score gauges, light and dark themes, and a baseline comparison.
- attest_flutter 1.x adapter: per-screen findings keyed by attest's own fingerprints, plus pass/fail outcomes for
  attest's 15 standard rules so accessibility is scored Lighthouse-style.
- Lighthouse 13 adapter. Scoring its output reproduces Lighthouse's own category scores.
- Lighthouse's log-normal metric scoring, ported exactly; weighted category and overall scores with configurable
  weights.
- Stable fingerprints and route normalization with go_router-style patterns, so the CI gate fails only on new
  findings or on score drops past configurable thresholds.
- Configuration in `flighthouse.yaml`, with errors that name the key, line, and column.
