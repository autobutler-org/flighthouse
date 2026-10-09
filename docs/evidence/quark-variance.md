# Quark run-to-run variance

Measured on 2026-10-09 for [#100](https://github.com/autobutler-org/flighthouse/issues/100). The data is in
[`quark-variance.json`](quark-variance.json) and the config in
[`quark-variance.collect.yaml`](quark-variance.collect.yaml). [ADR 0027](../adr/0027-quark-gate-tolerances.md)
draws the conclusions.

## Scope: one instance, not one commit

Every number here applies only to the quark instance at `http://odroid.lan:8080` as it was on 2026-10-09. It is not
quark `d8d2618e` and not the phase-2 dataset in `test/fixtures/quark/d8d2618e`, so these scores are not comparable to
[the phase-2 summary](../phases/phase-2.md). The owner approved auditing this instance.

What could be observed about it without an admin session:

| Item | Value |
| --- | --- |
| `GET /version.json` | `{"app_name":"quark","package_name":"quark","version":"0.49.1"}` |
| Flutter engine revision (`flutter_bootstrap.js`) | `deb287481e3ce9468f3434937ced4240a70539ca` |
| `GET /api/v0/auth/status` | `{"accessRequestsEnabled":true,"setup":true}` |
| `main.dart.js` sha256 | `95adcdf1aad0686deae09d3a84dc8c73eb97f03dbe6200e570ac47ca17d51225` |
| `index.html` sha256 | `0ce2853e18e7d2cb84479b6bbfce25aa53d9aba77bd9bcd3c094e73f1e229304` |
| Backend commit | Unknown. `GET /api/v0/version` needs an admin session and was not queried. |

Both hashes were the same when the files were fetched again after the runs (2026-10-09T22:13:42Z). The account was
an existing one that the owner supplied through `FLIGHTHOUSE_USERNAME` and `FLIGHTHOUSE_PASSWORD`. No account was
created, nothing was uploaded or changed, and the setup flow was not run. Each run signed in once, which leaves a
session on the instance. Terms and host choices are stored in the browser, not on the server.

The audited routes are `/files`, `/photos`, and `/settings/general`. They show that account's own data, so the
gallery and file contents are whatever the instance held.

## Recipe

The web runner builds and serves an app itself. It cannot point at a remote origin (ADR 0023). To audit the build
this instance serves, its frontend was copied unchanged and served by the runner. The sign-in steps then add the
instance as the backend host, using the same steps as the phase-2 recipe in
[`SOURCE.md`](../../test/fixtures/quark/d8d2618e/SOURCE.md).

1. Copy the frontend. Fetch each file of a quark web build from the instance, with `GET /` for `index.html`, because
   `/index.html` redirects there. Skip any path that comes back as HTML, which is the single-page fallback. For this
   instance, 56 files matched a local `build/web` listing, and none fell back. CanvasKit loads from `gstatic.com`,
   as `flutter_bootstrap.js` decides, so the runs needed internet access.
2. Put [`quark-variance.collect.yaml`](quark-variance.collect.yaml) in a directory `cfg/`, beside the copy in
   `odroid-web/`. Its build command is `true`, so `collect` serves the copy as it is. Everything below `serve` is the
   phase-2 config.
3. Collect serially, saving `raw/` after each run:

   ```sh
   export FLIGHTHOUSE_QUARK_NAME=Odroid
   export FLIGHTHOUSE_QUARK_HOST=http://odroid.lan:8080
   export FLIGHTHOUSE_USERNAME=<owner-supplied>
   export FLIGHTHOUSE_PASSWORD=<owner-supplied>
   for i in $(seq -w 1 15); do
     rm -rf runs/current
     dart run bin/flighthouse.dart --config cfg/collect.yaml collect
     cp -r runs/current/raw runs/run-$i
   done
   ```

4. Use run 01 as the baseline (`--report-dir runs/run-01 baseline --update`), then run `ci --report-dir runs/run-NN`
   for every run.
5. For the replays in `gateReplay`, compose the per-route raw files from the recorded runs into new report
   directories and run the real `flighthouse ci` on each. A median-of-N set takes, for each route, the run whose
   Lighthouse performance score is the median of the N. That simulates a runner change that does not exist.
   `scoreOnlyGateFailed` recomputes the verdict from the reported scores, ignoring new findings. That simulates the
   rule ADR 0027 proposes and is not current behavior.

The desktop-preset variant was a second set of 12 runs. The only change was
`lighthouse.command: [npx, --yes, lighthouse@13.5.0, --preset=desktop]`.

Versions: flighthouse `6506f22d312d`, Chrome 152.0.7977.42 (Puppeteer 3.26.0), Lighthouse 13.5.0 on Node 26.8.2,
axe-core 4.11.1. The machine was Linux with 8 CPUs, shared with other agents. Its one-minute load average, sampled
every 30 seconds from run 02 on, was 9.2 to 30.1 during the default runs and 2.2 to 7.5 during the variant.

## Results, default runner settings

The runner passes `--form-factor=desktop` and desktop screen emulation, but no throttling. Lighthouse therefore
applied its default simulated mobile throttling: 150 ms RTT, 1.6 Mbps, and 4× CPU.

- **15 of 15 collections succeeded.** Every Lighthouse result had no `runtimeError`, and its final URL was the
  requested route.
- **axe is stable.** The raw `violations` and `incomplete` results were identical in all 15 runs. So were all 117 axe
  fingerprints, which matched the variant runs too.
- **Accessibility and best practices did not move.** The combined a11y score was 86.62 and best practices 61.54 in
  every run. On `/files`, `/photos`, and `/settings/general`, the Lighthouse scores were 91, 94, and 94 for
  accessibility and 62 for best practices on all three. Best practices is lower than in phase 2 because
  `is-on-https` fails on the plain-HTTP backend.
- **Performance is bimodal.** 39 of 45 route runs scored 54 to 59, with simulated LCP of 888 to 1599 ms. The other 6
  scored exactly 35, with simulated LCP of 7850 to 8035 ms: run 04 on all three routes, run 02 and run 12 on
  `/files`, and run 10 on `/photos`. Observed LCP overlaps in the two groups, 59 to 404 ms against 102 to 460 ms.
  The 8-second value comes from the simulation, not from a slower page.
- **Combined spread, in points:** perf 34.98 to 58.92 (range 23.94) and overall 60.91 to 71.17 (range 10.26).
  Without the 35-point mode, the largest pairwise drop is 2.72 for perf and 1.16 for overall.
- **LCP sits on a scoring boundary.** Lighthouse scores LCP 0.9 at 1200 ms, and flighthouse emits a finding below
  0.9. Of the 39 normal-mode samples, 27 were at or below 1197 ms and 12 at or above 1203 ms. The
  `largest-contentful-paint` finding appeared in 8 of 15 runs on `/files`, 3 on `/photos`, and 6 on
  `/settings/general`. Its severity changed between moderate and serious under the same fingerprint.
- **The other unstable fingerprints are `info`:** `image-delivery-insight` and `forced-reflow-insight`.

Gate verdicts with the default gate:

| Comparison | Failed | Failure reasons |
| --- | ---: | --- |
| `ci` on runs 01–15 against run 01 | 5 / 15 | score drops and new LCP findings |
| Every ordered pair of single runs | 109 / 210 | 62 new LCP finding only, 37 both, 10 score drop only |
| Median of 3, baseline runs 01–03 | 36 / 220 | 17 new LCP finding only, 11 both, 8 score drop only |
| Median of 5, baseline runs 01–05 | 0 / 252 | — |
| Median of 5, baseline runs 06–10 | 84 / 252 | 63 new LCP finding only, 3 both, 18 score drop only |
| Median of 5, baseline runs 11–15 | 246 / 252 | new LCP finding only |

Every new finding that failed the gate was `largest-contentful-paint`. Using scores alone, with overall 2 and perf
5, still failed 47/210 single pairs, 19/220 median-of-3 sets, and 21/756 median-of-5 sets. Each of these failures
included a route in the 35-point mode.

## Results, `--preset=desktop`

The preset sets 40 ms RTT, 10 Mbps, and 1× CPU, still simulated.

- **12 of 12 collections succeeded.**
- **The 35-point mode did not appear.** Combined perf ranged 57.98 to 60.83 (range 2.85) and overall 70.77 to 71.99
  (range 1.22). Per-route performance ranged 56–60 on `/files`, 56–61 on `/photos`, and stayed at 61 on
  `/settings/general`. Accessibility and best practices were unchanged.
- **LCP is still two-valued.** 32 of 36 route runs were 239 to 272 ms. Four were 1373 to 1430 ms, above 1200 ms, so
  they produced a moderate finding: run 04 on `/files`, run 08 on `/files` and `/photos`, and run 10 on `/photos`.
  Observed LCP for those four was 66 to 101 ms.
- **`ci` against run 01: 3 of 12 failed,** all on a new moderate LCP finding. Across all ordered pairs, 31 of 132
  failed, all for the same reason, and none on score. Using scores alone, overall 2 and perf 5 failed 0 of 132.

These 12 runs came later, while the machine load was lower, so they are not a controlled comparison with the default
runs.

## Not verified

- The backend commit and the account's data volume. The data volume is visible only to the account.
- Whether the bimodal simulated LCP is caused by machine load, by the instance, or by Lighthouse's simulation. Load
  was sampled but not controlled.
- The median-of-N and score-only results are replays of recorded runs, not live runs of changed code.
- Ten consecutive live `ci` runs with one verdict. No configuration measured here achieved that: 5 of 15 runs failed
  against run 01 with the defaults, and 3 of 12 with `--preset=desktop`.
