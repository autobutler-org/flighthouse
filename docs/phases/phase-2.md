# Phase 2 summary

Epic #16, written 2026-10-09 for #28. The [self-contained report](../reports/quark-phase-2.html) and
[JSON report](../reports/quark-phase-2.json) come from one authenticated collection of quark `d8d2618e`. The
[provenance](../../test/fixtures/quark/d8d2618e/SOURCE.md) records the source, backend, dataset, tool versions,
hashes, and exact recipe.

## Results

| Category | Combined score |
| --- | ---: |
| Overall | 74 |
| Accessibility | 88 |
| Performance | 58 |
| Best practices | 81 |
| Responsiveness | Not measured |
| Memory | Not measured |

| Signed-in route | Lighthouse performance | Lighthouse accessibility | Best practices | axe violations (impact × nodes) |
| --- | ---: | ---: | ---: | --- |
| `/files` | 58 | 95 | 81 | aria-command-name serious ×1, region moderate ×5 |
| `/photos` | 58 | 94 | 81 | label critical ×1, nested-interactive serious ×6, region moderate ×1 |
| `/settings/general` | 59 | 94 | 81 | label critical ×2, nested-interactive serious ×2, region moderate ×13 |

There are 157 findings: 6 critical, 85 serious, 22 moderate, and 44 informational. Of the 85 serious ones, 69 are
axe "needs review" (`incomplete`) results: 67 color-contrast checks where axe could not determine the background
over Flutter's canvas, and 2 `aria-prohibited-attr`. They are open questions, not confirmed failures. The confirmed
serious failures are `nested-interactive` (each photo tile is a button containing its own **More** button),
`aria-command-name`, and Lighthouse's total-blocking-time and speed-index metrics. Critical findings are unlabeled
form controls, including the gallery's zoom slider.

## What works

| Exit criterion | Evidence |
| --- | --- |
| Runner on a real quark source and separate backend | quark `main` at `d8d2618e`, release web build via quark's own `make build/frontend/web`; backend compiled from the same commit with an isolated home directory |
| Authenticated routes with real form sign-in | A fresh Chrome accepted terms, added the backend through quark's host picker, typed into the real sign-in form, and reached `/files`. Lighthouse kept the session for all three routes. Every `finalDisplayedUrl` equals its requested route, with no `runtimeError` |
| Startup semantics with real nodes | Quark's own `ensureSemantics()` (#2919), no local change. The runner's semantics check passed, and axe results include 47, 49, and 79 distinct semantics nodes on the three routes |
| Populated gallery | Six byte-reproducible JPEGs and two documents were uploaded before collection; `/photos` axe output covers all six tiles (`aria-label="photo-01.jpg"` through `photo-06.jpg`) |
| Viewport and versions | 1280×800, scale factor 1, desktop form factor, the same for Lighthouse and axe. Chrome 152.0.7977.42 (Puppeteer 3.26.0), `lighthouse@13.5.0`, and axe-core 4.11.1 with a recorded script hash |
| Recorded outputs and recipe | Unedited raws under `test/fixtures/{lighthouse/13.5.0,axe/4.11.1}/quark-d8d2618e`; the exact [`collect.yaml`](../../test/fixtures/quark/d8d2618e/collect.yaml) and `make run/quark/web` |
| Gate behavior | `test/quark_validation_test.dart`: unchanged input passes (`0 new, 0 fixed, 157 unchanged`). Baselining without `/photos` and then adding it fails on real new `nested-interactive` serious findings and leaves the baseline unchanged. Invalid UTF-8 axe input exits 3 with "the gate was not evaluated" and cannot replace the baseline |
| Root CI stays Node-free | `make test/cli` now includes `make test/quark/web`, which replays the imported raws. Root CI already runs it in its Node-free image |

## What was assumed

- **The backend host is added through quark's UI.** Quark's web build targets its own origin (`/`), and the runner's
  static server does not proxy `/api` (ADR 0023). The sign-in steps therefore add `http://127.0.0.1:18431` as a
  second Quark and accept its terms. This adds five UI steps that a backend-served deployment would not have.
- **The selectors are structural.** Quark's buttons carry their names as text, not `aria-label`, and the add-host
  fields are labeled by hint text that disappears once they hold a value. A first attempt with
  `input[aria-label="Nickname (e.g. Home)"]` failed correctly with "input did not retain the typed value", because
  that selector stops matching after typing. The working selectors are positional (`+`, `:nth-child(… of :has())`)
  and will break when quark rearranges these screens.
- **No readiness selector.** Quark has no `role="main"`, and no single selector is shared by the terms page and
  every audited route. Readiness is therefore Flutter's first frame plus a nonempty semantics tree. axe ran after
  sign-in waited for the Files filter chips, and `/photos` evidently rendered its data, but no route waits for a
  data-specific marker.
- **`needs review` is serious.** The axe adapter maps `incomplete` results to findings at their reported impact,
  which makes canvas-backed contrast checks dominate the serious count.
- **The report commit is the config directory's.** `report` stamps `git rev-parse` of the config's directory. The
  published report was rendered with the same config placed in the quark checkout (stamped `d8d2618e`); the replay
  config under `test/fixtures` would stamp the flighthouse commit instead.

## App-side opt-in changes

None were needed or made. Startup semantics is already on in quark `main` (#2919). The run used an isolated owner
account, backend data directory, and dataset; nothing was pushed to quark.

Quark changes that would make the recipe simpler and less fragile (not made, for the quark maintainers):

- `Semantics(identifier: …)` or `aria-label`-bearing names on the terms, host, and sign-in controls.
- Real labels on the add-host fields instead of hint text only. This is also an accessibility defect: once
  filled, both inputs have an empty accessible name.
- A `role="main"` region on the routed pages.

## Remaining manual review

- The 69 axe "needs review" results, mostly contrast over the canvas. attest's raster contrast (phase 1) is the
  better signal for these; the browser checks cannot see Flutter's painted colors.
- Whether `nested-interactive` on the photo tiles and the unlabeled zoom slider are real screen reader barriers.
  Neither was checked with a screen reader.
- Keyboard and focus order, which neither tool measures.

## Not measured, or not representative

- **Responsiveness and memory** remain unmeasured (phase 3).
- **Performance is single-run.** A second collection about ten minutes later, on the same build, backend, and data,
  kept every accessibility finding and score identical. `/photos` LCP rose from 1.1 s to 8.1 s, and the combined
  performance score dropped from 58 to 50. The default gate (5-point perf allowance, `minor` new-finding threshold)
  failed that unchanged run on a new `largest-contentful-paint` finding. Do not gate quark performance on a single
  run until variance is measured or the threshold is configured for it. These scores are a desktop baseline for
  this dataset only and replace the earlier mobile experiment, which is not comparable.
- **Lighthouse fingerprint churn.** `image-delivery-insight` on `/files` named the splash image in one run and no
  node in the other, changing its fingerprint. It is informational, but it shows that not every Lighthouse insight
  has a stable target.
- **Platforms.** The run used Linux with the default Chrome sandbox. Native macOS and hosted runners did not run the
  quark workflow; the separate web workflow's hosted check covers only the small fixture app.

## Validation run in this session

- Two live `flighthouse collect` runs of `collect.yaml` against quark `d8d2618e` (one with the queued
  `puppeteer_browser.dart` click-focus fix applied, one without). Both exited 0 with three Lighthouse and three axe
  files.
- `make check`, `make test` (586 tests passing; run with `TMPDIR` on the home volume because this machine's `/tmp`
  quota was exhausted), and `make test/cli` (phase-1 quark, phase-2 quark web, and the e2e fixture gates all passed).
- Hosted checks on the merge stack have not been inspected yet.
