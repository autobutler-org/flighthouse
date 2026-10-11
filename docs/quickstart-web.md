# Quickstart: Flutter web apps

This guide takes a Flutter web app from nothing to a passing `flighthouse ci` run. `collect` builds the app with
semantics enabled, serves the build on `127.0.0.1`, signs in if configured, and runs Lighthouse and axe on each
route. `report`, `ci`, and `baseline` only read what `collect` wrote.

The configuration is specified in [ADR 0023](adr/0023-web-runner-configuration.md). A working example is the web
fixture in [`integration/web_fixture/`](../integration/web_fixture/flighthouse.yaml), which `make run/web-fixture`
collects and gates.

## Prerequisites

| Tool | Version used by the web workflow | Needed by |
| --- | --- | --- |
| Dart SDK | `^3.13.0` (the version Flutter ships is enough) | every command |
| Flutter | 3.47.7 stable | `collect` (builds the app) |
| Node.js | 22 | `collect` (runs Lighthouse) |
| Lighthouse | 13.5.0, `npm install -g lighthouse@13.5.0` | `collect` |
| Chrome | 152.0.7977.42, downloaded by `collect` | `collect` |
| axe-core | 4.11.1, downloaded by `collect` | `collect` |

You do not install Chrome or axe yourself. The first `collect` downloads the Chrome build pinned by Puppeteer into
`~/.cache/flighthouse/chrome` and axe-core into `~/.cache/flighthouse/axe`, then reuses them. On Linux, Chrome
needs `unzip` and its shared libraries; [`chrome_libraries.sh`](../integration/web_fixture/tool/chrome_libraries.sh)
lists the Debian and Ubuntu packages.

The web runner is newer than the 0.1.0 release on pub.dev, so install flighthouse from the repository:

```sh
dart pub global activate --source git https://github.com/autobutler-org/flighthouse.git
flighthouse --version
```

Make sure `~/.pub-cache/bin` is on your `PATH`.

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

Commit `flighthouse.yaml` and `flighthouse-baseline.json`. Add `.flighthouse/` to `.gitignore`.

### Every key

This is the web fixture's configuration with the defaults written out:

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
    timeoutSeconds: 90
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
  enable semantics itself. Quark's run uses `[make, build/frontend/web, FLUTTER_BUILD_MODE=release]`.
- `routes` are absolute paths, collected in order. Duplicates are rejected.
- `readiness` waits for Flutter's first frame and a nonempty semantics tree, then for `selector` if set.
  `timeoutSeconds` also bounds navigation and every auth step.
- `lighthouse.command` can be `[npx, --yes, lighthouse@13.5.0]` instead of a global install.
- `axe.scriptPath` can point at a local `axe.min.js` instead of downloading `axe.version`.
- `sources.lighthouse` and `sources.axe` cannot be set together with `web`. Other `sources`, such as `attest`, can.

### Sign-in and credentials

`auth` runs once, in the same browser Lighthouse and axe use, before the first route. Steps are `type`, `click`, and
`wait`, each with a CSS `selector`. Flutter puts semantics labels in `aria-label` and `Semantics(identifier: …)` in
`flt-semantics-identifier`, which make the most stable selectors.

A `type` step reads its value from the environment variable named in `valueFromEnv`, and only while `collect` runs.
Credentials never go in the config. Set them before collecting:

```sh
export FLIGHTHOUSE_USERNAME=…
export FLIGHTHOUSE_PASSWORD=…
```

`collect` checks every `valueFromEnv` before it touches the page. It does not start a backend or create an account;
both must already exist. The first route is opened after sign-in, and it must not redirect.

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
browser Chrome/152.0.7977.42
collected 2 lighthouse files
collected 2 axe files
$ flighthouse baseline --update
wrote flighthouse-baseline.json with 24 findings
$ flighthouse ci
web-fixture: overall 69 | a11y 100 | perf 35 | responsiveness n/a | memory n/a | best-practices 81
0 new, 0 fixed, 24 unchanged
gate passed
```

`ci` without a baseline exits 3 with `baseline …: not found. Run: flighthouse baseline --update`. `flighthouse
baseline` without `--update` prints the same `new, fixed, unchanged` counts as `ci` and changes nothing.

In CI, run `collect` and then `ci`, and commit baseline changes from a local `baseline --update`. Exit codes:

| Code | Meaning |
| --- | --- |
| 0 | collected, or the gate passed |
| 1 | the gate failed |
| 2 | usage or configuration error |
| 3 | unusable input or a missing tool; the gate was not evaluated |

On GitHub's `ubuntu-latest` runners Chrome cannot start with its sandbox, so the web workflow sets
`FLIGHTHOUSE_CI_CHROME_NO_SANDBOX=true` for those jobs only. See [ADR 0026](adr/0026-linux-chrome-launch.md) before
setting it anywhere else.

## Read the report

The summary line scores each category from 0 to 100. A web run measures `a11y`, `perf`, and `best-practices`.
`responsiveness` and `memory` show `n/a` and are left out of `overall`.

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

The first word of a custom `build.command` could not be started.

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

Export the named variable before `collect`.

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

#### `config: sources.axe (line …, column …): axe cannot be imported when web is configured`

`web` writes `raw/axe` and `raw/lighthouse` itself. Remove `sources.axe` or `sources.lighthouse`.

#### `could not read …/raw/lighthouse: not found; run flighthouse collect first`

`report`, `ci`, or `baseline` ran before a successful `collect`. `ci` prints `the gate was not evaluated because
some inputs were unusable:` first and exits 3. `baseline` prints `the baseline was not touched` and leaves it as it
was.

#### `baseline …: not found. Run: flighthouse baseline --update`

There is no baseline yet. Create it from a run you accept and commit it.
