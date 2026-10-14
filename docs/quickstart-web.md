# Quickstart: Flutter web apps

This guide takes a Flutter web app from nothing to a passing `flighthouse ci` run. `collect` builds the app with
semantics enabled, serves the build on `127.0.0.1`, signs in if configured, and runs Lighthouse and axe on each
route. `report`, `ci`, and `baseline` only read what `collect` wrote.

The configuration is specified in [ADR 0023](adr/0023-web-runner-configuration.md). A working example is the web
fixture in [`integration/web_fixture/`](../integration/web_fixture/flighthouse.yaml), which `make run/web-fixture`
collects and gates. Its [README](../integration/web_fixture/README.md) lists the fixture's routes, manifests, and
checks.

## Prerequisites

| Tool | Version used by the web workflow | Needed by |
| --- | --- | --- |
| Dart SDK | `^3.13.0` (the version Flutter ships is enough) | every command |
| Flutter | 3.47.7 stable | `collect` (builds the app) |
| Node.js | 22 | `collect` (runs Lighthouse) |
| Lighthouse | 13.5.0, `npm install -g lighthouse@13.5.0` | `collect` |
| Chrome | 152.0.7977.42, downloaded by `collect` | `collect` |
| axe-core | 4.11.1, downloaded by `collect` | `collect` |
| Memory and time | about 115 s and 4.3 to 5.1 GB peak for Quark, almost all in `flutter build web` | `collect` |

The memory and time figures come from [#139](https://github.com/autobutler-org/flighthouse/issues/139): `collect`
on Quark with one route, on an 8-core, 16 GB machine. Memory climbs through the build; Chrome, Lighthouse, and axe
then use about 0.6 GB for about 15 s. A machine with 4 to 8 GB, or one already busy with other programs, may run out
of memory during the build. To leave the build out of `collect`, see
[Reuse an existing build](#reuse-an-existing-build).

You do not install Chrome or axe yourself. The first `collect` downloads the Chrome build pinned by Puppeteer into
`~/.cache/flighthouse/chrome` and axe-core into `~/.cache/flighthouse/axe`, then reuses them. On Linux, Chrome
needs `unzip` and its shared libraries; [`chrome_libraries.sh`](../integration/web_fixture/tool/chrome_libraries.sh)
lists the Debian and Ubuntu packages.

Install flighthouse 0.2.0 or later from pub.dev:

```sh
dart pub global activate flighthouse
flighthouse --version
```

Make sure `~/.pub-cache/bin` is on your `PATH`.

An app's own build can need more than this table. Quark's backend, for example, is built with Go (see
[Quark's configuration](#quarks-configuration)).

## Turn on semantics in the app

Lighthouse and axe read the DOM. A Flutter web app only exposes its semantics tree to the DOM after something
enables it, so the app has to opt in at startup. The default build command passes
`--dart-define=FLIGHTHOUSE_SEMANTICS=true`; read it in `main`:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('FLIGHTHOUSE_SEMANTICS')) {
    WidgetsBinding.instance.ensureSemantics();
  }
  runApp(const MyApp());
}
```

An app that already calls `ensureSemantics()` unconditionally needs no change. Without either, `collect` stops with
`no Flutter semantics nodes were exposed` (see [Readiness and routes](#readiness-and-routes)).

Routes are URL paths, so the fixture uses `usePathUrlStrategy()`. Each route must still be the displayed URL once
the page is ready.

## Configure

Put `flighthouse.yaml` in the Flutter project root. The smallest web configuration is:

```yaml
app: my_app
web:
  routes:
    - /
```

Everything else has a default: the project is the config file's directory, the build is
`flutter build web --release --dart-define=FLIGHTHOUSE_SEMANTICS=true` with output in `build/web`, the server picks
a free port, the viewport is 1280 × 800 at scale 1, Lighthouse runs as `lighthouse`, and axe is 4.11.1. Raw output
and reports go to `.flighthouse/`, and the baseline is `flighthouse-baseline.json`. Relative paths resolve against
the config file's directory.

Commit `flighthouse.yaml` and `flighthouse-baseline.json`; both live next to each other in the app repository's
root unless you move them. Add `.flighthouse/` to `.gitignore`. `collect` also runs the build, which writes
`build.outputDir` (`build/web` by default, inside Flutter's own `build/` directory) and whatever else a custom build
command writes. flighthouse does not clean those up, so ignore them the way the app already does.

### Every key

This is the web fixture's configuration with every key written out. The values are the defaults, except `app`,
the extra `--dart-define` in `build.command`, `routes`, `readiness.selector`, and `auth`, which have no default.
The fixture's own [`flighthouse.yaml`](../integration/web_fixture/flighthouse.yaml) also moves `reportDir` and
`baseline` under `build/` and raises `readiness.timeoutSeconds` to 90.

```yaml
app: web-fixture
reportDir: .flighthouse
baseline: flighthouse-baseline.json
web:
  projectDir: .
  build:
    command:
      - flutter
      - build
      - web
      - --release
      - --dart-define=FLIGHTHOUSE_SEMANTICS=true
      - --dart-define=FIXTURE_API_ORIGIN=http://127.0.0.1:8090
    outputDir: build/web
  serve:
    port: 0
  routes:
    - /account
    - /public
  readiness:
    timeoutSeconds: 30
    selector: '[role="main"]'
  viewport:
    width: 1280
    height: 800
    deviceScaleFactor: 1
  auth:
    url: /login
    steps:
      - type: type
        selector: 'input[aria-label="Username"]'
        valueFromEnv: FLIGHTHOUSE_USERNAME
      - type: type
        selector: 'input[aria-label="Password"]'
        valueFromEnv: FLIGHTHOUSE_PASSWORD
      - type: click
        selector: '[role="button"][flt-semantics-identifier="sign-in"]'
      - type: wait
        selector: '[role="main"][aria-label="Account"]'
  lighthouse:
    command: [lighthouse]
  axe:
    version: 4.11.1
gate:
  minSeverity: minor
  maxScoreDrop: {overall: 2, perf: 5}
```

- `build.command` is an executable and its arguments, run in `projectDir` with no shell. A custom command must
  enable semantics itself. Quote any element YAML would read as something other than a string: `[true]` is a
  boolean and fails with `expected a non-empty string`, while `['true']` runs the `true` command.
- `routes` are absolute paths, collected in order. Duplicates are rejected.
- `readiness` waits for Flutter's first frame and a nonempty semantics tree, then for `selector` if set.
  `timeoutSeconds` defaults to 30 and also bounds navigation and every auth step. Raise it for a slow first load
  or a slow sign-in.
- `lighthouse.command` can be `[npx, --yes, lighthouse@13.5.0]` instead of a global install.
- `axe.scriptPath` can point at a local `axe.min.js` instead of downloading `axe.version`.
- `sources.lighthouse` and `sources.axe` cannot be set together with `web`. Other `sources`, such as `attest`, can.

### Sign-in and credentials

`auth` runs once, in the same browser Lighthouse and axe use, before the first route. Steps are `type`, `click`, and
`wait`, each with a CSS `selector`. Flutter puts semantics labels in `aria-label` and `Semantics(identifier: …)` in
`flt-semantics-identifier`, which make the most stable selectors.

A `type` step reads its value from the environment variable named in `valueFromEnv`, and only while `collect` runs.
Credentials never go in `flighthouse.yaml`. Set them before collecting, or keep them in a
[hosts file](#credentials-per-backend-host):

```sh
export FLIGHTHOUSE_USERNAME=…
export FLIGHTHOUSE_PASSWORD=…
```

`collect` checks every value before it touches the page. It does not start a backend or create an account; both
must already exist. The first route is opened after sign-in, and it must not redirect.

### Credentials per backend host

An app that signs into a backend needs that backend's URL, a username, and a password. To keep them together, and to
switch backends without re-exporting variables, list each backend in `.flighthouse/hosts.yaml` beside
`flighthouse.yaml`:

```yaml
hosts:
  https://app.example.com:
    username: flighthouse
    password: flighthouse
```

The file holds plain-text credentials, so it must stay out of git. The `.flighthouse/` ignore rule above covers it.
Each entry takes exactly `username` and `password`, both non-empty strings. Quote a value YAML would read as a number.

A `type` step takes a value from the selected entry with `valueFromHost`, which is `url` (the entry's key),
`username`, or `password`. A step may set `valueFromHost`, `valueFromEnv`, or both:

```yaml
- type: type
  selector: 'input[aria-label="Server"]'
  valueFromHost: url
- type: type
  selector: 'input[aria-label="Username"]'
  valueFromHost: username
  valueFromEnv: FLIGHTHOUSE_USERNAME
- type: type
  selector: 'input[aria-label="Password"]'
  valueFromHost: password
  valueFromEnv: FLIGHTHOUSE_PASSWORD
```

Select an entry with `--host`. When the file has exactly one entry, it is selected without the option:

```sh
flighthouse collect --host https://app.example.com
```

- With a host selected, `valueFromHost` wins, even when `valueFromEnv` is also set.
- With no host selected, a step reads `valueFromEnv`. A step that has only `valueFromHost` fails and says to pass
  `--host`.
- The file is read only when `--host` is passed or a step sets `valueFromHost`. A config that uses only
  `valueFromEnv` works as before.

In CI there is no committed hosts file. Either give each step a `valueFromEnv` fallback and export the variables from
the CI secret store, or write the file from secrets before `collect`:

```sh
mkdir -p .flighthouse
cat > .flighthouse/hosts.yaml <<EOF
hosts:
  $APP_HOST:
    username: "$APP_USERNAME"
    password: "$APP_PASSWORD"
EOF
flighthouse collect
```

A username or password from the file is only typed into the page. It never appears in a report, a raw output, an
error message, or a log line.

### Quark's configuration

A fresh browser that opens Quark is sent to `/terms` until it accepts the terms and signs in, so the minimal
configuration with `routes: [/]` fails with `could not verify displayed web route /: browser displayed /terms after
readiness`. Collecting Quark needs `auth`, and `auth` needs a running Quark backend with an existing account.

The phase-2 run's configuration is recorded in
[`test/fixtures/quark/d8d2618e/collect.yaml`](../test/fixtures/quark/d8d2618e/collect.yaml). It builds with
`[make, build/frontend/web, FLUTTER_BUILD_MODE=release]`, waits up to 60 seconds, and signs in through Quark's terms
page, host picker, and sign-in form. Its [`SOURCE.md`](../test/fixtures/quark/d8d2618e/SOURCE.md) records the
versions used (Flutter 3.47.7, a backend built with `go build ./cmd/quark`) and how the backend, owner account, and
data were set up. The selectors are positional and break when Quark rearranges those screens; the
[phase 2 summary](phases/phase-2.md#what-was-assumed) explains why.

## Run

```sh
flighthouse collect             # build, serve, sign in, run Lighthouse and axe on each route
flighthouse report              # write .flighthouse/report.json and report.html
flighthouse baseline --update   # accept the current findings and scores as the baseline
flighthouse ci                  # report, then gate against the baseline
```

A first run of the fixture prints:

```text
$ flighthouse collect
building the web app: flutter build web --release --dart-define=FLIGHTHOUSE_SEMANTICS=true --dart-define=FIXTURE_API_ORIGIN=http://127.0.0.1:8090
starting Chrome
browser Chrome/152.0.7977.42
auditing /account with lighthouse
auditing /public with lighthouse
auditing /account with axe
auditing /public with axe
collected 2 lighthouse files
collected 2 axe files
$ flighthouse baseline --update
wrote flighthouse-baseline.json with 24 findings
$ flighthouse ci
web-fixture: overall 69 | a11y 100 | perf 35 | responsiveness n/a | memory n/a | best-practices 81
0 new, 0 fixed, 24 unchanged
gate passed
```

`collect` prints a line as it builds the web app, starts Chrome, and audits each route with Lighthouse and then axe,
so a long build shows which step is running. The first run also downloads Chrome.

### Reuse an existing build

`collect` runs `build.command` every time; it never checks whether the build in `outputDir` is current. To skip the
build, for example while iterating on routes or `auth`, or on a machine short of memory, build once yourself and set
the build command to `true`, which does nothing:

```yaml
web:
  build:
    command: ['true']
    outputDir: build/web
```

Quote it: unquoted `[true]` is a YAML boolean and fails with `expected a non-empty string`. `collect` then serves
whatever is in `outputDir`, which must contain `index.html`, so rebuild it with semantics enabled whenever the app
changes. [The quark variance measurement](evidence/quark-variance.md) collected a copied build this way, with its
[configuration](evidence/quark-variance.collect.yaml). Put the real build command back before committing, or keep
this setting in a separate config file passed with `--config`.

### The baseline

The baseline, `flighthouse-baseline.json`, is a snapshot of the findings and scores you have accepted. `ci` compares
the current run against it: findings that are not in it are new, findings in it that are gone are fixed, and score
drops are measured from its scores. The gate fails only on new findings and score drops, so existing problems do not
block a merge.

`baseline --update` accepts every current finding, whatever it is. The first baseline therefore accepts everything
the app has today, including real failures and `Needs review:` results; read the first report before committing
it. Update the baseline when you have fixed findings (`ci` lists them as fixed), when you deliberately accept a new
finding or a lower score, or when you add a route. Run `baseline --update` locally after a `collect`, review the
diff of `flighthouse-baseline.json`, and commit it.

`ci` without a baseline exits 3 with `baseline …: not found. Run: flighthouse baseline --update`, not 0, so a CI job
fails until a baseline is committed. `flighthouse baseline` without `--update` prints the same `new, fixed,
unchanged` counts as `ci` and changes nothing.

### In CI

In CI, run `collect` and then `ci`, and commit baseline changes from a local `baseline --update`. Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | collected, or the gate passed |
| 1 | the gate failed |
| 2 | usage or configuration error |
| 3 | unusable input or a missing tool; the gate was not evaluated |

Treat 1 as a result: the change introduced a new finding or a score drop. Fix it, or, if it is accepted, update the
baseline. Treat 2 and 3 as a broken job: the configuration, a tool, the build, or the browser failed, and the gate
never ran, so the result says nothing about the change. Fix the cause and run the job again.

On GitHub's `ubuntu-latest` runners Chrome cannot start with its sandbox, so the web workflow sets
`FLIGHTHOUSE_CI_CHROME_NO_SANDBOX=true` for those jobs only. See [ADR 0026](adr/0026-linux-chrome-launch.md) before
setting it anywhere else.

flighthouse's own [`.github/workflows/web.yml`](../.github/workflows/web.yml) is a working example: its `web` job
installs Flutter 3.47.7, Node 22, Lighthouse 13.5.0, and Chrome's libraries, then collects the web fixture and runs
the gate. A job for your app follows the same steps. The sketch below is adapted from that job and has not been run
as written; replace the build, credentials, and paths with your app's:

```yaml
jobs:
  flighthouse:
    runs-on: ubuntu-latest
    env:
      FLIGHTHOUSE_CI_CHROME_NO_SANDBOX: "true"
      FLIGHTHOUSE_USERNAME: ${{ secrets.FLIGHTHOUSE_USERNAME }}
      FLIGHTHOUSE_PASSWORD: ${{ secrets.FLIGHTHOUSE_PASSWORD }}
    steps:
      - uses: actions/checkout@v7
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: 3.47.7
      - uses: actions/setup-node@v7
        with:
          node-version: 22
      - run: npm install --global lighthouse@13.5.0
      - run: tool/chrome_libraries.sh
      - run: |
          dart pub global activate --source git https://github.com/autobutler-org/flighthouse.git
          echo "$HOME/.pub-cache/bin" >> "$GITHUB_PATH"
      - run: flighthouse collect
      - run: flighthouse ci
```

`tool/chrome_libraries.sh` is a copy of [`chrome_libraries.sh`](../integration/web_fixture/tool/chrome_libraries.sh)
in your repository. Drop the credentials if the app has no `auth`, and keep in mind that `auth` needs a backend the
job can reach.

## Read the report

The summary line scores each category from 0 to 100. A web run measures three:

- `a11y`: Lighthouse's accessibility audits and axe's rules.
- `perf`: Lighthouse's performance audits and metrics, such as Largest Contentful Paint.
- `best-practices`: Lighthouse's best-practices audits.

`responsiveness` and `memory` show `n/a` and are left out of `overall`. `overall` is the weighted mean of the
measured categories; by default `a11y` and `perf` weigh 3 times as much as `best-practices`. `report.html` colors
each score the way Lighthouse does: 90 to 100 passes, 50 to 89 is average, and 0 to 49 fails. The bands are only a
reading aid; the gate compares scores with the baseline, not with the bands.

`report.html` is self-contained and has these sections:

- **Scores**: overall and per category.
- **Compared with the baseline**: new findings, written by `ci` only.
- **Findings**: grouped by category and severity, each with its route, rule, and target element when there is one.
- **Fixed since the baseline**: findings that disappeared, also `ci` only. Accept them with `flighthouse baseline --update`.
- **Measurements**: Lighthouse metrics such as Largest Contentful Paint, with their scores.

The gate fails on a new finding at or above `gate.minSeverity` (default `minor`; `info` never fails) or a score drop
larger than `gate.maxScoreDrop`. A new finding that carries a measured metric, such as Largest Contentful Paint, is
counted as new and shown in the report, but does not fail by itself: the category score drop gates it
([ADR 0027](adr/0027-quark-gate-tolerances.md)). Adding a route to the fixture after baselining fails like this
(excerpt):

```text
8 new, 0 fixed, 7 unchanged
FAIL new moderate best-practices finding on /account: deprecations: Uses deprecated APIs
FAIL new serious a11y finding on /account: color-contrast: Needs review: Elements must meet minimum color contrast ratio thresholds
…
gate failed
```

`Needs review:` marks an axe `incomplete` result: axe could not decide, often because Flutter paints text on a
canvas. Treat those as questions to check, not confirmed failures.

Performance scores vary between runs on the same build. [The quark variance measurement](evidence/quark-variance.md)
found drops of up to 2.85 perf points and 1.22 overall points between runs with desktop throttling, inside the default
`maxScoreDrop`. If your app varies more, measure it the same way before raising a tolerance.

Every value that decides the verdict is a config key. Each is optional, and these are the defaults
([ADR 0028](adr/0028-configurable-gate-tolerances.md)):

```yaml
web:
  lighthouse:
    throttling:
      rttMs: 40
      throughputKbps: 10240
      cpuSlowdownMultiplier: 1
gate:
  minSeverity: minor
  maxScoreDrop: {overall: 2, a11y: 2, perf: 5, responsiveness: 2, memory: 2, best-practices: 2}
  metricFindings: score
scoring:
  lighthouse:
    passingScore: 0.9
    seriousScore: 0.5
```

- `web.lighthouse.throttling` is the network and CPU throttling Lighthouse simulates. The defaults are the values
  of Lighthouse's desktop preset. `rttMs` is at least 0, `throughputKbps` is above 0, and `cpuSlowdownMultiplier`
  is at least 1.
- `gate.metricFindings: new` makes a new finding that carries a metric fail the gate at or above `minSeverity`, like
  any other new finding. `score` leaves it to the category score drop.
- `scoring.lighthouse.passingScore` is the Lighthouse audit score below which an audit is a finding.
  `seriousScore` is the score below which a measured audit is `serious` instead of `moderate`. Both run from 0 to 1,
  and `seriousScore` cannot be above `passingScore`.

Regenerate the baseline with `flighthouse baseline --update` after changing `throttling` or `scoring.lighthouse`:
scores and findings taken under different values are not comparable.

## Troubleshooting

Every message below is printed by flighthouse to standard error. `…` stands for a path, selector, or detail from your
run.

### Missing tools

#### `Lighthouse not found. Install it with: npm install -g lighthouse`

`collect` runs `lighthouse.command` with `--version` and could not start it. Install Lighthouse, or set
`lighthouse.command: [npx, --yes, lighthouse@13.5.0]`.

#### `could not read the Lighthouse version from … --version: printed no version; reinstall it with: npm install -g lighthouse`

The command started but did not print a version, so it is probably not Lighthouse. The same message says `an
unusable version` when it printed something else.

#### `Flutter not found. Install it with: follow https://docs.flutter.dev/get-started/install and put flutter on PATH`

The build command is `flutter` and it is not on `PATH`.

#### `… not found. Install it with: install it or change web.build.command to a command that is installed`

The executable named first in a custom `build.command`, shown at the start of the message, could not be started.
Install that program and put it on `PATH`, or change `build.command` to one that is installed.

#### `… Node.js 22 is required to run Lighthouse; install it and put node on PATH`

Lighthouse is installed but `node` is not on `PATH`, so its `lighthouse --version` check could not start. Install
Node.js 22 and make sure `node` runs from the same shell as `flighthouse`.

#### `axe-core … not found. Install it with: set web.axe.scriptPath to a local axe.min.js or choose a published axe-core version`

`axe.version` is not a published axe-core release. Use a released version such as `4.11.1`, or point
`axe.scriptPath` at a script you already have.

### Build and serve

#### `flutter build web … exited with code …: …`

The build failed. The text after the colon is the first line of its standard error. Run the same command in
`projectDir` to see all of it.

#### `could not use web build output …: not found after a successful build`

The build succeeded but `build.outputDir` does not exist. It is relative to `projectDir`. If the directory exists
but has no `index.html`, the message is `could not use web entrypoint …/index.html`.

#### `could not bind web server 127.0.0.1:…: …`

`serve.port` is in use. Use `0` to let the system choose.

### Chrome

#### `could not acquire Chrome into …: unzip is required to unpack Chrome; install it, for example: apt install unzip`

The first download of Chrome needs `unzip`. A download that takes longer than five minutes fails with `timed out
after 300000 ms`.

#### `could not launch Chrome …: Chrome is missing system libraries; install them, for example: apt install libnss3 libatk-bridge2.0-0 libgbm1 libasound2`

Chrome's shared libraries are missing. `chrome_libraries.sh` installs the full list on Debian and Ubuntu.

#### `could not launch Chrome …: Chrome could not start with its sandbox enabled. Configure a supported Chrome sandbox for this host; flighthouse does not disable the sandbox automatically.`

The host blocks Chrome's sandbox, as Ubuntu's AppArmor does on GitHub runners. See
[ADR 0026](adr/0026-linux-chrome-launch.md) for the CI-only `FLIGHTHOUSE_CI_CHROME_NO_SANDBOX` switch.

#### `… Chrome's renderer crashed while flighthouse drove the page. …`

The page crashed during readiness, sign-in, or axe. Lighthouse reports the same thing as `lighthouse: …: Chrome's
renderer crashed while Lighthouse loaded the page (TARGET_CRASHED)`. Check free memory and load, then run again.

### Readiness and routes

#### `could not verify Flutter semantics …: no Flutter semantics nodes were exposed; enable startup semantics in the application build`

The page rendered but has no semantics tree. Add the [startup opt-in](#turn-on-semantics-in-the-app), and keep
`--dart-define=FLIGHTHOUSE_SEMANTICS=true` in a custom build command.

#### `could not wait for browser selector …: timed out after … ms`

`readiness.selector` never became visible within `timeoutSeconds`. Check the selector against the page's
`flt-semantics` elements, or raise the timeout for a slow first load. Navigation and the first frame can time out
the same way, with `open browser page` or `verify Flutter semantics` in place of `wait for browser selector`.

#### `could not verify displayed web route …: browser displayed … after readiness`

The route redirected, usually to a sign-in page. Add `auth`, or collect public and signed-in routes in separate
configs. flighthouse never audits a redirect under the requested route's name.

#### `lighthouse: …: final displayed URL was …; requested …`

The same redirect, seen by Lighthouse after readiness had passed.

#### `lighthouse: …: Lighthouse reported a runtime error: …`

Lighthouse loaded the page but could not audit it. The code and message after the colon come from Lighthouse.

### Sign-in

#### `could not read web authentication credential web.auth.steps[…].valueFromEnv (…): environment variable is missing or empty`

Export the named variable before `collect`, or give the step a `valueFromHost` and select a host.

#### `could not read web authentication credential web.auth.steps[…].valueFromHost (…): no host is selected; …`

The step has no `valueFromEnv` fallback and no host entry was selected. The end of the message says what to do: pass
`--host` with one of the listed hosts, create `.flighthouse/hosts.yaml`, or add an entry to it.

#### `could not select host …: no entry in …/.flighthouse/hosts.yaml; defined hosts: …`

`--host` must match an entry's key exactly, including the scheme and any port.

#### `could not read …/.flighthouse/hosts.yaml: not found; --host needs an entry under hosts in this file`

Create the file beside `flighthouse.yaml`. See [Credentials per backend host](#credentials-per-backend-host).

#### `config: …/.flighthouse/hosts.yaml: hosts.… (line …, column …): …`

The hosts file is not in the expected shape. The message names the key, such as
`hosts.https://app.example.com.password`, and never a value from the file.

#### `could not run web authentication step … (…) …: …`

A step failed. The message names the step number (counting from 1), its type, and its selector, never the value it
typed. The reason is one of:

- `timed out after … ms`: the selector did not appear. A `wait` that times out right after the sign-in click
  usually means the credentials were rejected or the backend is not running.
- `input did not retain the typed value`: the selector stopped matching after typing. Selectors that depend on
  hint text do this; prefer `aria-label` or `flt-semantics-identifier`.
- `selected input was unavailable`, `selected element could not be clicked`, `selector did not become ready`: the
  element matched but could not be used.

### Config, report, and gate

#### `… create flighthouse.yaml in … (see docs/quickstart-web.md#configure)`

There is no `flighthouse.yaml` in the working directory. Run flighthouse from the app's root, pass `--config` with
the file's path, or create the file as [Configure](#configure) shows.

#### `config: … expected a non-empty string`

A value that should be a string is empty or was read as another type. Unquoted `true`, `false`, `null`, and numbers
are not strings in YAML; quote them, as in `command: ['true']`.

#### `config: sources.axe (line …, column …): axe cannot be imported when web is configured`

`web` writes `raw/axe` and `raw/lighthouse` itself. Remove `sources.axe` or `sources.lighthouse`.

#### `could not read …/raw/lighthouse: not found; run flighthouse collect first`

`report`, `ci`, or `baseline` ran before a successful `collect`. `ci` prints `the gate was not evaluated because
some inputs were unusable:` first and exits 3. `baseline` prints `the baseline was not touched` and leaves it as it
was.

#### `baseline …: not found. Run: flighthouse baseline --update`

There is no baseline yet. Create it from a run you accept and commit it.
