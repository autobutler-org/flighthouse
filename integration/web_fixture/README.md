# Web fixture

A small Flutter web app that flighthouse collects end to end in CI. It has routes with known defects planted in
them, routes with a known performance cost, and routes with a known layout, plus a manifest for each group that
records what flighthouse should report. The check scripts under [`tool/`](tool/) compare a real collection against
those manifests.

[`flighthouse.yaml`](flighthouse.yaml) is the fixture's own configuration. The
[web quickstart](../../docs/quickstart-web.md) walks through it key by key and lists the tools a run needs
(Flutter, Node, Lighthouse, Chrome and its libraries).

## Routes

| Route | What it plants | Recorded in |
| --- | --- | --- |
| `/login` | The sign-in form. `collect` drives it through the `auth` steps in `flighthouse.yaml` and does not audit it. | `flighthouse.yaml` |
| `/account` | A page behind sign-in. It asks the auth backend for `/account` with the stored token and redirects to `/login` without one. | `flighthouse.yaml`, checked by `check_raw.py` |
| `/public` | A page with one line of text and no sign-in. | `flighthouse.yaml`, checked by `check_raw.py` |
| `/planted` | Every planted accessibility defect at once. | [`planted.json`](planted.json) |
| `/planted?defects=<keys>` | Only the listed defects, by the `toggle` key in `planted.json`: `label`, `image-alt`, `target-size`, `contrast`, `duplicate-name`, comma separated. `defects=none` turns them all off. | [`planted.json`](planted.json) |
| `/perf/control` | One line of text, the baseline the slowed routes are measured against. | [`performance.json`](performance.json) |
| `/perf/heavy` | 4000 colored text tiles built in the first frame. | [`performance.json`](performance.json) |
| `/perf/janky` | A 4 second animation that blocks the main thread for 120 ms every frame. | [`performance.json`](performance.json) |
| `/responsive/control` | Six 112px cards in a `Wrap` that reflows to the viewport. | [`responsive.json`](responsive.json) |
| `/responsive/overflow` | Six 112px cards 8px apart in a `Row`, 712px wide, clipped below that width. | [`responsive.json`](responsive.json) |

Any other path renders `/public`. The fixture's `flighthouse.yaml` audits only `/account`, `/public`, and
`/planted`. The check scripts write their own configurations for the other routes.

### The planted defects

Each entry in `planted.json` names the defect, its toggle key, its route, category, and rule, the tools expected to
report it (`sources`), and whether it is `detectable`. An undetectable entry carries a `reason`.

| Defect | Toggle | Rule | Sources | Detectable |
| --- | --- | --- | --- | --- |
| text field without a label | `label` | `label` | axe, Lighthouse | yes |
| image without alternative text | `image-alt` | `role-img-alt` | axe | yes |
| two adjacent 8px buttons | `target-size` | `target-size` | Lighthouse | yes |
| light gray text on white | `contrast` | `color-contrast` | axe, Lighthouse | no |
| two buttons both named Save | `duplicate-name` | none | none | no |

## Running the checks

| Target | What it does |
| --- | --- |
| `make run/web-fixture` | Builds the fixture, collects it, and runs every check below. CI runs this in `.github/workflows/web.yml`. |
| `make run/web-fixture/performance` | Re-records `performance.json` over `RUNS` runs (default 5). |
| `make run/web-fixture/responsive` | Re-records `responsive.json` at a wide and a narrow viewport. |
| `make run/web-fixture/variance` | Collects `RUNS` times (default 3) and prints each score's and planted defect's spread. |
| `make test/web-fixture-tools` | Unit tests the check scripts offline against recorded data. `make test` runs it too. |

`make run/web-fixture` runs [`tool/run_fixture.sh`](tool/run_fixture.sh). It starts the auth backend
([`tool/auth_backend.dart`](tool/auth_backend.dart)) on port 8090 with `fixture-user` and `fixture-password` unless
`FLIGHTHOUSE_USERNAME`, `FLIGHTHOUSE_PASSWORD`, or `FIXTURE_API_PORT` say otherwise, runs `collect` and `report`
into `build/web-fixture/`, then runs the checks in this order:

1. [`check_raw.py`](tool/check_raw.py) reads the raw Lighthouse and axe output. It passes when there is exactly one
   result per audited route (`/account`, `/public`, `/planted`), every Lighthouse run used desktop settings at 1280
   by 800, device scale 1, desktop throttling, and kept storage, and the auth backend's log shows `POST /login 200`
   before `GET /account 200`.
2. [`check_planted.py`](tool/check_planted.py) reads `report.json`. A defect counts as detected when every one of
   its `sources` reported its rule on its route and category, ignoring "Needs review:" findings. It fails when a
   `detectable` defect is not detected, and when an undetectable one is reported by any of its sources, which means
   `planted.json` needs updating.
3. [`check_gate.py`](tool/check_gate.py) exercises `ci`. It writes a baseline with `baseline --update` and expects
   `ci` to pass. It adds a serious axe finding to the raw output and expects `ci` to exit 1 without touching the
   baseline. It then corrupts the axe JSON and expects both `ci` and `baseline --update` to exit 3 and leave the
   baseline unchanged.
4. [`check_toggles.py`](tool/check_toggles.py) collects `/planted?defects=none`, baselines it, and expects `ci` to
   pass. It turns on the first detectable defect's toggle and expects `ci` to exit 1 with exactly that defect's
   rule from its sources as the new findings. It turns the toggle off and expects `ci` to pass again.
5. [`check_performance.py`](tool/check_performance.py) collects the `/perf/*` routes and computes each route's
   weighted performance score from `report.json`. Each score must fall within its recorded `min` and `max` widened by
   `tolerance` (the control route has no upper bound), and each slowed route must score at least `tolerance` below
   the control.
6. [`check_responsive.py`](tool/check_responsive.py) collects the `/responsive/*` routes at each viewport in
   `responsive.json`. It fails when the responsiveness score or the responsiveness finding count on either route
   differs from what was recorded.

Steps 4 to 6 reuse the build from step 1 instead of rebuilding.

## Re-recording the manifests

The three re-recording targets reuse the build that `make run/web-fixture` left in `build/web`, so run that first.

```sh
make run/web-fixture
make run/web-fixture/performance RUNS=5
make run/web-fixture/responsive
```

- **`performance.json`**: `run/web-fixture/performance` collects the `/perf/*` routes `RUNS` times, refuses fewer
  than two, and fails if any run breaks the separation from the control. It writes each route's `scores`, `min`,
  and `max`, the date, the run count, and the Lighthouse version. `tolerance`, `cost`, and `control` are kept as
  they were. The script's `--machine` option sets the `recorded.machine` text, which otherwise stays the same. The
  current ranges add one run on the GitHub Actions runner to five local runs.
- **`responsive.json`**: `run/web-fixture/responsive` collects both routes at each viewport and writes the score and
  finding counts per category under `observed`, plus `difference`, the overflowing route's narrow minus wide
  responsiveness finding count.
- **`planted.json`** has no recording target. Edit it by hand when a defect is added to `PlantedPage` in
  [`lib/main.dart`](lib/main.dart) or when `check_planted.py` reports that an undetectable defect is now detected.

Commit a re-recorded manifest together with the change that moved it.

## Reading the variance numbers

```sh
make run/web-fixture
make run/web-fixture/variance RUNS=5
```

`run/web-fixture/variance` collects `/public` and `/planted` (all defects on) `RUNS` times from the existing build,
writes `build/web-fixture-variance/variance.json`, and keeps each run's `report.json` under `runs/`. It prints two
tables. The score table gives each category's min, median, and max across runs, `null` when nothing measured it,
and a failure count equal to the number of runs where `collect` or `report` failed. The planted defect table scores
each run 1 when the defect was detected and 0 when not, and its failure count adds the runs where detection
disagreed with `detectable`.

[`docs/evidence/web-fixture-variance.md`](../../docs/evidence/web-fixture-variance.md) records a five-run sample
and what it says:

- Accessibility, best-practices, and every planted defect's detection were identical in all runs, so on the fixture
  any change in them is a real change.
- Performance carries all the noise, up to 0.0567 between runs, and the overall score moves only because
  performance is part of it. A performance difference of that size is not evidence of a change.
- Responsiveness and memory are `null`, so they have no spread.
- Five runs on a shared machine bound the spread from below. They do not set a gate tolerance.

## What the checks do not cover

- **Undetectable defects.** Low contrast and duplicate button names are planted but neither axe 4.11.1 nor
  Lighthouse 13.5.0 reports them on a Flutter web build. `check_planted.py` only proves they stay unreported. A
  regression flighthouse cannot see in these two will not fail anything.
- **One toggle.** `check_toggles.py` turns on only the first detectable defect, `label`. The other toggles are
  exercised only together, through `/planted`.
- **No responsiveness signal.** No web adapter emits a responsiveness score or finding yet
  ([#161](https://github.com/autobutler-org/flighthouse/issues/161),
  [ADR 0034](../../docs/adr/0034-web-responsive-layout-out-of-scope.md)). `responsive.json` records a `null` score
  and a difference of 0 on the overflowing route. `check_responsive.py` is a guard that fails when that changes, not
  proof that overflow is caught. The narrow viewport's lower a11y count on `/responsive/overflow` comes from
  clipped cards dropping out of the semantics tree, not from a layout check.
- **Memory.** No route plants a memory cost, and the score is `null` in every run.
- **Performance beyond Lighthouse.** The performance check uses the Lighthouse-derived perf score only. Frame
  timing from `integration_test` is not collected from the fixture
  ([ADR 0032](../../docs/adr/0032-web-frame-timing-source.md)). The ranges are recorded on one machine and one CI
  run, so a slower or busier runner can fall outside them.
- **One viewport for accessibility.** Every check except `check_responsive.py` audits at 1280 by 800.
