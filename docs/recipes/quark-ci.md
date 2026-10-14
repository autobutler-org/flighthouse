# Recipe: gate quark's CI on flighthouse

Status: draft for [#102](https://github.com/autobutler-org/flighthouse/issues/102). Nothing here has been run. No
workflow, config, or baseline below has been executed against quark, against any quark backend, or on a GitHub
runner. [What was not verified](#what-was-not-verified) lists every gap, and [Next steps](#next-steps) says what the
maintainer does to turn this into a quark pull request.

The recipe is built from flighthouse's own [`web.yml`](../../.github/workflows/web.yml), the
[Flutter web quickstart](../quickstart-web.md), the phase-2 quark config in
[`test/fixtures/quark/d8d2618e/collect.yaml`](../../test/fixtures/quark/d8d2618e/collect.yaml), and quark's own
`build.yml`, `.github/actions/setup-flutter`, `.github/actions/setup-node`, and `.github/path-filters.yml` as they
are on quark's `main` (read, not changed).

## What the quark pull request adds

| File | Purpose |
| --- | --- |
| `flighthouse.yaml` | The web runner config: build, routes, sign-in. [Below](#flighthouseyaml). |
| `flighthouse-baseline.json` | The accepted findings and scores. Written on a runner, [not by hand](#the-initial-baseline). |
| `.github/workflows/flighthouse.yml` | Collect, gate, upload the report. [Below](#the-workflow). |
| `.github/path-filters.yml` | A `flighthouse` set, so the job skips when nothing it reads changed. |
| `scripts/chrome_libraries.sh` | A copy of [`chrome_libraries.sh`](../../integration/web_fixture/tool/chrome_libraries.sh). |
| `.gitignore` | `.flighthouse/`, which holds raw output, reports, and the hosts file. |

Quark already enables semantics on the web
([quark#2919](https://github.com/autobutler-org/quark/pull/2919)), so the app needs no code change.

## The backend CI signs into

Every audited route is behind sign-in, and sign-in needs a quark backend with an existing account
([quickstart: Quark's configuration](../quickstart-web.md#quarks-configuration)). The web runner serves the frontend
it builds on `127.0.0.1` and the sign-in steps add a backend host through quark's own host picker, as in the phase-2
recipe ([`SOURCE.md`](../../test/fixtures/quark/d8d2618e/SOURCE.md#sign-in)).

This draft signs into a backend named by a CI secret: a quark instance reachable from GitHub-hosted runners, with a
dedicated audit account and a fixed data set. That is the open decision in this recipe:

- **A standing audit instance** (this draft). Needs a public HTTPS quark instance, an account that exists only for
  audits, and data nobody changes. Its backend version is not the pull request's, so a backend change shows up in
  every pull request's run until the baseline is updated.
- **A backend built in the job from the same commit.** Results would follow the pull request exactly, but the job
  would have to create the owner account. Quark derives the auth key in the client, so the phase-2 run created it
  through the real `/setup` form in a browser. Nothing in flighthouse or this recipe does that, and inventing it here
  would be guessing at quark's setup flow.

Best practices depends on the backend: `is-on-https` failed on the plain-HTTP instance in
[the variance measurement](../evidence/quark-variance.md#results-default-runner-settings). Use HTTPS.

### Secrets

Set three repository secrets in quark. None of them is ever written into a committed file or the workflow.

| Secret | Value |
| --- | --- |
| `FLIGHTHOUSE_QUARK_HOST` | The backend URL exactly as typed into quark's host picker, scheme and port included. |
| `FLIGHTHOUSE_USERNAME` | The audit account's username. |
| `FLIGHTHOUSE_PASSWORD` | The audit account's password. |

The workflow writes them into `.flighthouse/hosts.yaml` before `collect`, as
[ADR 0029](../adr/0029-host-credentials-file.md) describes for CI, and deletes the file after `collect` whether it
passed or not. flighthouse types those values into the page and never writes them to a report, raw output, error,
or log line (ADR 0029, Secrecy). GitHub also masks secret values in the job log.

Pull requests from forks get no secrets, so the job skips them rather than failing on an empty hosts file.

## `flighthouse.yaml`

The phase-2 config, with the paths set for the quark repository root and each credential step reading the hosts file
first and the environment second. A developer with a local `.flighthouse/hosts.yaml` and CI with a written one use
the same file; a developer without one exports the four variables instead.

```yaml
app: quark
web:
  build:
    command:
      - make
      - build/frontend/web
      - FLUTTER_BUILD_MODE=release
    outputDir: build/web
  routes:
    - /files
    - /photos
    - /settings/general
  readiness:
    timeoutSeconds: 60
  auth:
    url: /terms
    steps:
      - type: wait
        selector: 'flt-semantics[role="group"] + flt-semantics[role="button"]'
      - type: click
        selector: 'flt-semantics[role="group"] + flt-semantics[role="button"]'
      - type: wait
        selector: 'flt-semantics[role="group"][aria-current] > flt-semantics[role="button"]'
      - type: click
        selector: 'flt-semantics[role="group"][aria-current] > flt-semantics[role="button"]'
      - type: wait
        selector: 'flt-semantics[role="radiogroup"] + flt-semantics[role="button"]'
      - type: click
        selector: 'flt-semantics[role="radiogroup"] + flt-semantics[role="button"]'
      - type: type
        selector: 'flt-semantics[role="alertdialog"] flt-semantics:nth-child(1 of :has(> input)) > input'
        valueFromEnv: FLIGHTHOUSE_QUARK_NAME
      - type: type
        selector: 'flt-semantics[role="alertdialog"] flt-semantics:nth-child(2 of :has(> input)) > input'
        valueFromHost: url
        valueFromEnv: FLIGHTHOUSE_QUARK_HOST
      - type: click
        selector: 'flt-semantics[role="alertdialog"] flt-semantics[role="button"]:last-child'
      - type: wait
        selector: 'flt-semantics[role="group"] + flt-semantics[role="button"]'
      - type: click
        selector: 'flt-semantics[role="group"] + flt-semantics[role="button"]'
      - type: type
        selector: 'input[aria-label="Username"]'
        valueFromHost: username
        valueFromEnv: FLIGHTHOUSE_USERNAME
      - type: type
        selector: 'input[aria-label="Password"]'
        valueFromHost: password
        valueFromEnv: FLIGHTHOUSE_PASSWORD
      - type: click
        selector: 'flt-semantics:has(> input[aria-label="Password"]) + flt-semantics[role="button"]'
      - type: wait
        selector: 'flt-semantics[role="checkbox"][aria-label="My files"]'
  lighthouse:
    command: [lighthouse]
  axe:
    version: 4.11.1
```

- There is no `gate` section and no `throttling` or `scoring` key: quark uses the defaults. [Gate
  tolerances](#gate-tolerances) says why and which of them are provisional.
- `FLIGHTHOUSE_QUARK_NAME` is the nickname typed into the host picker. It is not a secret; the workflow sets it.
- The selectors are structural and were recorded on quark `d8d2618e`. They break when quark rearranges the terms,
  host picker, or sign-in screens, and they have not been checked against quark's current `main`.
- `reportDir` (`.flighthouse`) and `baseline` (`flighthouse-baseline.json`) keep their defaults, so the baseline
  sits in the repository root.
- `make build/frontend/web` also copies the build into `internal/server/public/`, which quark's `.gitignore`
  already covers.

## The workflow

`.github/workflows/flighthouse.yml` in quark. It follows quark's conventions (`changes` job with
`dorny/paths-filter`, `setup-flutter` and `setup-node` composite actions, caches saved on `main` only) and
flighthouse's `web` job (Lighthouse 13.5.0, Chrome's libraries, `FLIGHTHOUSE_CI_CHROME_NO_SANDBOX` on
`ubuntu-latest` per [ADR 0026](../adr/0026-linux-chrome-launch.md)).

```yaml
name: Flighthouse
on:
  pull_request:
  merge_group:
  workflow_dispatch:
    inputs:
      update-baseline:
        description: Write flighthouse-baseline.json from this run and upload it instead of gating
        type: boolean
        default: false
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
permissions:
  contents: read
defaults:
  run:
    shell: bash
env:
  FLIGHTHOUSE_REF: v-0.2.0
  LIGHTHOUSE_VERSION: 13.5.0
  CHROME_VERSION: 152.0.7977.42
jobs:
  changes:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    outputs:
      flighthouse: ${{ steps.filter.outputs.flighthouse }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v7
      - name: Filter paths
        id: filter
        if: github.event_name == 'pull_request' || github.event_name == 'merge_group'
        continue-on-error: true
        uses: dorny/paths-filter@v4
        with:
          filters: .github/path-filters.yml
  flighthouse:
    needs: changes
    if: >-
      needs.changes.outputs.flighthouse != 'false' &&
      (github.event_name != 'pull_request' ||
       github.event.pull_request.head.repo.full_name == github.repository)
    runs-on: ubuntu-latest
    timeout-minutes: 45
    env:
      FLIGHTHOUSE_CI_CHROME_NO_SANDBOX: "true"
      FLIGHTHOUSE_QUARK_NAME: Audit
      FLIGHTHOUSE_QUARK_HOST: ${{ secrets.FLIGHTHOUSE_QUARK_HOST }}
      UPDATE_BASELINE: ${{ inputs.update-baseline == true }}
    steps:
      - name: Checkout code
        uses: actions/checkout@v7
      - name: Setup Flutter
        uses: ./.github/actions/setup-flutter
      - name: Setup Node
        uses: ./.github/actions/setup-node
      - name: Install Lighthouse
        run: npm install --global "lighthouse@${LIGHTHOUSE_VERSION}"
      - name: Install the libraries Chrome needs
        run: scripts/chrome_libraries.sh
      - name: Install flighthouse
        run: |
          dart pub global activate --source git \
            https://github.com/autobutler-org/flighthouse.git --git-ref "${FLIGHTHOUSE_REF}"
          echo "${HOME}/.pub-cache/bin" >> "${GITHUB_PATH}"
      - name: Restore Chrome and axe
        id: browser-cache
        uses: actions/cache/restore@v6
        with:
          path: ~/.cache/flighthouse
          key: flighthouse-${{ runner.os }}-${{ env.FLIGHTHOUSE_REF }}-chrome-${{ env.CHROME_VERSION }}
      - name: Print tool versions
        run: |
          flutter --version
          node --version
          lighthouse --version
          flighthouse --version
      - name: Note whether a baseline is committed
        id: baseline
        run: |
          if [[ -f flighthouse-baseline.json ]]; then
            echo "committed=true" >> "${GITHUB_OUTPUT}"
          else
            echo "committed=false" >> "${GITHUB_OUTPUT}"
          fi
      - name: Write the hosts file from secrets
        env:
          QUARK_USERNAME: ${{ secrets.FLIGHTHOUSE_USERNAME }}
          QUARK_PASSWORD: ${{ secrets.FLIGHTHOUSE_PASSWORD }}
        run: |
          umask 077
          mkdir -p .flighthouse
          jq -n \
            --arg host "${FLIGHTHOUSE_QUARK_HOST}" \
            --arg username "${QUARK_USERNAME}" \
            --arg password "${QUARK_PASSWORD}" \
            '{hosts: {($host): {username: $username, password: $password}}}' \
            > .flighthouse/hosts.yaml
      - name: Collect
        run: |
          flighthouse collect --host "${FLIGHTHOUSE_QUARK_HOST}" 2>&1 | tee "${RUNNER_TEMP}/collect.log"
          if ! grep -qxF "browser Chrome/${CHROME_VERSION}" "${RUNNER_TEMP}/collect.log"; then
            echo "::error::collect did not use the pinned Chrome ${CHROME_VERSION}"
            exit 1
          fi
      - name: Delete the hosts file
        if: always()
        run: rm -f .flighthouse/hosts.yaml
      - name: Save Chrome and axe
        if: github.ref == 'refs/heads/main' && steps.browser-cache.outputs.cache-hit != 'true'
        uses: actions/cache/save@v6
        with:
          path: ~/.cache/flighthouse
          key: ${{ steps.browser-cache.outputs.cache-primary-key }}
      - name: Gate against the committed baseline
        if: steps.baseline.outputs.committed == 'true' && env.UPDATE_BASELINE != 'true'
        run: flighthouse ci
      - name: Write a baseline from this run
        if: steps.baseline.outputs.committed != 'true' || env.UPDATE_BASELINE == 'true'
        run: |
          flighthouse baseline --update
          flighthouse report
      - name: Keep the report
        if: always()
        uses: actions/upload-artifact@v7
        with:
          name: flighthouse-report
          if-no-files-found: warn
          path: |
            .flighthouse/report.json
            .flighthouse/report.html
            .flighthouse/raw
      - name: Keep the new baseline
        if: steps.baseline.outputs.committed != 'true' || env.UPDATE_BASELINE == 'true'
        uses: actions/upload-artifact@v7
        with:
          name: flighthouse-baseline
          path: flighthouse-baseline.json
          if-no-files-found: error
      - name: Fail until a baseline is committed
        if: steps.baseline.outputs.committed != 'true'
        run: |
          echo "::error::no flighthouse-baseline.json is committed; review the flighthouse-report artifact, then commit the flighthouse-baseline artifact"
          exit 1
```

The `flighthouse` set added to quark's `.github/path-filters.yml`. The job reads the web build's inputs plus its own
files; with a standing backend, a Go-only change cannot move its result.

```yaml
flighthouse:
  - *flutter
  - web/**
  - flighthouse.yaml
  - flighthouse-baseline.json
  - scripts/chrome_libraries.sh
  - .github/workflows/flighthouse.yml
```

Notes on the workflow:

- **flighthouse version.** pub.dev has only 0.1.0, which has no web runner. The workflow activates the `v-0.2.0` tag
  from git. Once 0.2.0 is on pub.dev, replace the step with `dart pub global activate flighthouse 0.2.0`.
- **Pinned Chrome.** `collect` downloads the Chrome build Puppeteer pins into `~/.cache/flighthouse/chrome`, and axe
  into `~/.cache/flighthouse/axe`. flighthouse does not commit a `pubspec.lock`, so activation resolves Puppeteer
  `^3.26.0` at install time. The `Collect` step therefore checks the `browser Chrome/…` line `collect` prints and
  fails on any other build, so a Puppeteer release cannot silently change the browser under the baseline. The cache
  key carries the same version.
- **Node.** Quark's `setup-node` installs Node from `.nvmrc` (24.21.0 today). flighthouse's own workflow runs
  Lighthouse 13.5.0 on Node 22, and the variance runs used Node 26.8.2; Node 24 was not tried.
- **Exit codes.** `ci` exits 1 when the gate fails, and 2 or 3 when the config, a tool, the build, the browser, or
  sign-in failed and the gate never ran ([quickstart: In CI](../quickstart-web.md#in-ci)). Both fail the job. Read
  the log before reading the report: a 3 says nothing about the change.
- **The artifact.** `flighthouse-report` holds `report.json`, the self-contained `report.html`, and the raw Lighthouse
  and axe output. It never contains `.flighthouse/hosts.yaml`: the paths are listed one by one and the file is
  deleted first. The phase-2 raw output was searched for every credential and session value and held none
  ([`SOURCE.md`](../../test/fixtures/quark/d8d2618e/SOURCE.md#raw-outputs)); this run's output has not been.
- **Time and memory.** About 115 s and 4.3 to 5.1 GB peak for one route on an 8-core machine
  ([quickstart prerequisites](../quickstart-web.md#prerequisites)), almost all in the Flutter build. Three routes add
  Lighthouse and axe time per route. `ubuntu-latest` has 16 GB.

## The baseline

The baseline, `flighthouse-baseline.json`, holds the findings and scores quark has accepted. `ci` fails only on a
finding missing from it or a score drop past a tolerance, so existing problems do not block a merge
([ADR 0009](../adr/0009-baseline-and-ci-gate.md)).

### The initial baseline

Write it on a GitHub runner, not on a laptop. Lighthouse's simulated scores depend on the machine, the variance
measurement saw them move with load, and quark's own CI is a different build, data set, and machine from the measured
instance ([ADR 0027](../adr/0027-quark-gate-tolerances.md), Open questions). A baseline from the runner is compared
against runs on the same kind of runner.

1. Open the quark pull request with the workflow, `flighthouse.yaml`, the path filter, the script, and the ignore
   rule, and without `flighthouse-baseline.json`.
2. The job sees no committed baseline. It collects, runs `flighthouse baseline --update` and `flighthouse report`,
   uploads both artifacts, and fails with `no flighthouse-baseline.json is committed`.
3. Download both: `gh run download <run-id> -n flighthouse-report -n flighthouse-baseline`.
4. Read `report.html` before accepting anything. `baseline --update` accepts every current finding, including real
   failures and `Needs review:` axe results; the quickstart's [baseline section](../quickstart-web.md#the-baseline)
   explains why. Open issues in quark for findings worth fixing; they stay accepted until fixed.
5. Commit `flighthouse-baseline.json` to the pull request. The next run gates against it and should pass.

The file is written with sorted keys and entries, so a regenerated baseline with nothing changed produces no diff.

### Fingerprint scheme v2

Each finding's fingerprint is a SHA-256 over `v2|source|rule|route|target`, with the route and target normalized
first ([ADR 0007](../adr/0007-fingerprints-and-normalization.md), [ADR 0024](../adr/0024-axe-target-identity.md)).
The message is not an input, so a reworded finding is not new. The baseline records `fingerprintVersion: v2`.

`ci` refuses a baseline fingerprinted with another scheme, with `it uses fingerprint scheme …, this run uses v2`,
because every finding would otherwise look new. flighthouse 0.1.0 wrote `v1` baselines, so quark's first baseline
must come from 0.2.0 or later. When a future flighthouse bumps the scheme, regenerate the baseline in the same quark
pull request that bumps `FLIGHTHOUSE_REF`; `baseline --update` is the migration.

### Updating the baseline on an intended change

Update it when a change is meant to move the result:

- findings were fixed, which `ci` lists as fixed and never fails on;
- a new finding or a lower score is accepted on purpose;
- a route was added or removed;
- `web.lighthouse.throttling` or `scoring.lighthouse` changed, which makes old and new scores incomparable
  ([ADR 0028](../adr/0028-configurable-gate-tolerances.md));
- `FLIGHTHOUSE_REF`, `LIGHTHOUSE_VERSION`, `CHROME_VERSION`, or the axe version changed;
- the standing audit backend was upgraded or its data changed.

Once the workflow is on quark's `main`, run it with `update-baseline` on the pull request's branch, then commit the
artifact in that pull request:

```sh
gh workflow run flighthouse.yml --ref <branch> -f update-baseline=true
gh run download <run-id> -n flighthouse-baseline
git diff flighthouse-baseline.json
```

Review the diff before committing: each added or removed finding and each score change should be one the pull
request explains. Say in the pull request why the baseline moved. `flighthouse baseline` without `--update` prints
the same `new, fixed, unchanged` counts as `ci` and writes nothing, for a preview from a local run.

A developer with a hosts file can also run `flighthouse collect && flighthouse baseline --update` locally. Use that
only for an a11y or best-practices change: performance scores taken on a laptop are not comparable with the runner's.

## Gate tolerances

The only sources are [ADR 0028](../adr/0028-configurable-gate-tolerances.md)'s configurable keys, all left at their
defaults, and the measurement in [`quark-variance.md`](../evidence/quark-variance.md) that
[ADR 0027](../adr/0027-quark-gate-tolerances.md) draws its numbers from. Nothing below was tuned for this recipe.

ADR 0027 is Accepted, but its decision 4 says quark's CI should not gate on flighthouse performance until ten
consecutive live `ci` runs give one verdict. [#113](https://github.com/autobutler-org/flighthouse/issues/113) shipped
the throttling and metric-finding changes, but its ten-run re-measurement is not recorded under `docs/evidence/`, and
the variance evidence lists it as not verified. Every number that rests on performance variance is therefore marked
**provisional**: it is ADR 0027's value, measured on one instance under uncontrolled load, never confirmed by live
runs of the shipped code.

| Key | Value | Measured basis | Status |
| --- | --- | --- | --- |
| `gate.minSeverity` | `minor` | All 117 axe fingerprints and the raw axe results identical in 27 of 27 runs | Firm for axe and binary audits |
| `gate.maxScoreDrop.a11y` | 2 | a11y 86.62 in every run; largest drop 0 | Firm |
| `gate.maxScoreDrop.best-practices` | 2 | 61.54 in every run; largest drop 0 | Firm |
| `gate.maxScoreDrop.perf` | 5 | Largest drop 2.85 over 132 pairs with desktop throttling, 2.72 without the 35-point mode | **Provisional** |
| `gate.maxScoreDrop.overall` | 2 | Largest drop 1.22 over 132 pairs; margin 0.78, the smallest | **Provisional** |
| `gate.metricFindings` | `score` | Score-only replay of the desktop runs failed 0 of 132 pairs; a replay, not a live run | **Provisional** |
| `web.lighthouse.throttling` | 40 ms, 10240 Kbps, 1× | 12 runs, later and under lower load; LCP still two-valued | **Provisional** |
| `scoring.lighthouse.passingScore` | 0.9 | Not measured; the default | Default |
| `scoring.lighthouse.seriousScore` | 0.5 | Not measured; the default | Default |
| `gate.maxScoreDrop.responsiveness`, `.memory` | 2 | Not measured on the web; both show `n/a` | Not applicable |

What the provisional rows mean for the workflow:

- A new axe finding or a new failing binary Lighthouse audit at `minor` or above fails the gate. That part did not
  vary in any measured run, and it is what "a pull request that adds a serious finding fails" in #102 exercises.
- A slower page fails only through a perf drop above 5 or an overall drop above 2. A new `largest-contentful-paint`
  finding is reported but does not fail by itself (`metricFindings: score`).
- Do not raise a tolerance to make a flaky run pass. ADR 0027 rejected that: covering the 35-point mode would take
  perf above 24 and overall above 10.3. If runs on quark's runners disagree, measure median-of-N Lighthouse runs next,
  as #113 says.

Before the job becomes a required check, confirm the provisional rows on quark's own runners: run the workflow on an
unchanged `main` ten times (`gh workflow run flighthouse.yml --ref main`, once per run, after the baseline is
committed) and record the verdicts. Ten of one verdict meets ADR 0027 decision 4 and covers #99's five-run exit
criterion. Until then, leave the check optional.

## What was not verified

- Nothing in this recipe has run. The workflow, the config, the path filter, and the baseline procedure are drafts.
  No `flighthouse collect`, `flutter build web`, or GitHub Actions run was made for it.
- Which backend CI signs into, and whether one reachable from GitHub-hosted runners exists, with an audit account and
  fixed data.
- The sign-in selectors on quark's current `main`. They were recorded on `d8d2618e`.
- Lighthouse 13.5.0 on Node 24.21.0 from quark's `.nvmrc`.
- That `dart pub global activate --source git … --git-ref v-0.2.0` resolves Puppeteer to the build that downloads
  Chrome 152.0.7977.42 today.
- That `jq` output is accepted as `.flighthouse/hosts.yaml`. JSON is valid YAML, but flighthouse's hosts parser has
  not been run on it.
- Run time and peak memory for three routes on `ubuntu-latest`.
- Every provisional tolerance above, on any machine.

## Next steps

For the maintainer, in order:

1. Decide the backend CI signs into, and create the audit account and data on it.
2. Add the three secrets to quark.
3. Open the quark pull request with the files in [What the quark pull request adds](#what-the-quark-pull-request-adds),
   adjusting this draft to anything quark's `main` has changed.
4. Follow [The initial baseline](#the-initial-baseline) to commit `flighthouse-baseline.json` in that pull request.
5. Show both hosted checks #102 asks for: the unchanged pull request passes, and a throwaway pull request that adds a
   serious finding fails.
6. After merging, run the ten unchanged runs in [Gate tolerances](#gate-tolerances), then make the check required.
