# `AGENTS.md`

## Purpose

These instructions tell coding agents how to work in this repository.
[`CLAUDE.md`](CLAUDE.md) imports this file, so this is the one place to edit. Never write a second copy of a
rule somewhere else.

flighthouse is an open-source (MIT) Dart package and CLI that produces one Lighthouse-style scored report for a
Flutter app, covering accessibility, performance, responsiveness, and memory, and works as a CI gate. It does not
audit anything itself. It ingests the outputs of existing tools (attest, Lighthouse, axe, integration_test
`TimelineSummary`, flutter_lighthouse), normalizes them to one schema, scores, diffs against a baseline, and
renders a report. The one new capability is a Flutter web runner that builds with semantics enabled, serves the
build, and drives Lighthouse and axe against it.

The first real target is [autobutler-org/quark](https://github.com/autobutler-org/quark), a Flutter web app.

### Repo map

The layout below is decided in [ADR 0003](docs/adr/0003-package-layout.md). Parts of it are built phase by phase, so
check that a directory exists before citing it.

```text
bin/flighthouse.dart          CLI entrypoint, nothing but a call into lib/src/cli
lib/flighthouse.dart          public library barrel
lib/src/result/               the in-repo sealed Result type
lib/src/model/                Finding, Report, Category, Severity, Metric, Fingerprint, Baseline
lib/src/config/               the immutable Config value and its YAML parser
lib/src/adapters/<tool>/      one directory per tool: raw output in, findings out
lib/src/pipeline/             normalize, dedupe, baseline diff, score
lib/src/render/               JSON and HTML renderers, pure, return a String
lib/src/io/                   the shell: files, processes, the browser, the clock
lib/src/cli/                  package:args commands and exit codes
packages/flighthouse_flutter/ companion package: flutter_test and integration_test helpers
example/                      pub.dev example
test/                         mirrors lib/src; fixtures under test/fixtures/<tool>/<tool-version>/
docs/adr/                     architecture decision records
docs/epics/                   epic drafts, one per phase
git/hooks/                    pre-commit and commit-msg hooks
```

### Where to read next

- [`docs/adr/`](docs/adr/README.md): every design decision and its status. A rule below that cites an ADR is
  only as settled as that ADR's status.
- [`docs/epics/`](docs/epics/README.md): the phases, their tasks, and their exit criteria.

## Working in this repository

### Use Makefile targets (always)

Use the existing targets to build, run, test, and check rather than crafting shell commands. If an action needs
to be repeatable, add a target. `make help` lists everything.

| Target            | What it does                                                         |
| ----------------- | -------------------------------------------------------------------- |
| `make setup`      | git hooks and `dart pub get`                                         |
| `make check`      | the whole gate: `check/format`, `check/lint`                         |
| `make check/pana` | score the package the way pub.dev does                               |
| `make fix`        | `dart fix --apply`, `dart format`                                    |
| `make test`       | every unit, fixture, and end-to-end test                             |
| `make test/cli`   | run the CLI's `ci` command against recorded fixtures                 |
| `make all`        | end-to-end run against a real local Quark (see below)                |
| `make release`     | tag the pubspec version on a clean, current `main` and push the tag  |

GNU make is required. On macOS use `gmake`.

A new target follows the existing naming: `check/...`, `test/...`, `setup/...`, `build/...`, `run/...`.

### What the checks enforce

`make check` is installed as a pre-commit hook (`make setup/hooks`), and CI runs the same targets, so nothing
here is advisory. `make setup/hooks` also installs a commit-msg hook that rejects AI attribution in a commit
message: a `Co-authored-by:` trailer naming Claude or an `anthropic.com` address, a "Generated with Claude Code"
footer, or a `claude.ai/code` session link.

- **Formatting**: `dart format --set-exit-if-changed`.
- **Analysis**: `dart analyze --fatal-infos` with `strict-casts`, `strict-inference`, and `strict-raw-types`
  (see [`analysis_options.yaml`](analysis_options.yaml)). Do not add an `// ignore:` to get a build green and do
  not disable a rule to avoid a fix.
- **Layering**: `test/architecture_test.dart` fails when a file outside `lib/src/io/` and `lib/src/cli/`
  imports `dart:io`, `dart:isolate`, or `package:puppeteer`, or when anything under `lib/` imports Flutter.
- **pub.dev score**: CI runs `make check/pana` and fails below full points (see
  [ADR 0018](docs/adr/0018-packaging-and-pub-dev.md)).

### Scope discipline

- **Advice is not a request for edits.** When asked to review, explain, coach, or advise, answer in chat and touch
  no files. Edit only when the request asks for a change.
- **Filing an issue is not implementing it.** When asked to write up an issue or a plan, stop there.
- **An issue belongs to its epic as a sub-issue, not a link.** Attach it with
  `gh api -X POST repos/autobutler-org/flighthouse/issues/<epic>/sub_issues -F sub_issue_id=<id>`, where `<id>` is the
  child's database id from `gh api repos/autobutler-org/flighthouse/issues/<N> --jq .id`, not its number. Confirm with
  `gh api repos/autobutler-org/flighthouse/issues/<N>/parent`.
- **Working an issue means owning it.** Before starting on a ticket, `gh issue edit <N> --add-assignee @me`.
- **Every ticket states its model scope.** `**Model scope: Opus.**` with a one-line reason. Opus is the default;
  Sonnet only for a mechanical, well-specified change with no design judgment.
- **Work one phase at a time.** Do not start a task from a later epic while the current one has open tasks.
  At the end of a phase, summarize what works, what was assumed, and what could not be verified.
- **Ask before a large change.** A new dependency, a new abstraction layer, a change to an Accepted ADR, or edits
  across more than about ten files get two or three options with tradeoffs before any code is written.
- **Build what was asked.** No mechanisms, config knobs, or abstractions nobody requested.
- **Never fork or vendor an upstream tool.** Propose a workaround in our code, a pinned version, or an upstream
  issue first.

### Decisions live in ADRs

- A design decision that someone could reasonably have made differently gets an ADR in `docs/adr/`, numbered
  above the highest existing one. [ADR 0001](docs/adr/0001-record-architecture-decisions.md) has the format.
- `Proposed` means not approved. Do not build on a Proposed ADR without the maintainer's sign-off.
- To change an Accepted decision, write a new ADR that supersedes it and update the old one's status line. Never
  rewrite an Accepted ADR's Decision section in place.

### Root cause over symptom

- **State the causal chain before writing a fix:** the input, the line responsible, and how you will prove it.
  A failing test or a fixture that reproduces it comes first.
- **Sweep for siblings.** Ask whether every adapter, category, and renderer has the same defect.
- **Fix the shared source of truth** (the schema, the scoring table, the common function) rather than patching one
  branch of a switch.

### Verification before claiming done

- Run `make check` and `make test` before every push.
- Report exactly what was run. Never write "verified by hand", "tested manually", or the like unless that
  verification happened in this session.
- A PR or commit never carries a Claude Code session link, and all prose and identifiers use American spelling.

## End-to-end run against Quark

`make all` (an alias of `make run/quark/e2e`) runs flighthouse against a real Quark, not a recording: it starts the
pinned Quark release, seeds a test household, builds or reuses Quark's web app, runs `collect`, `report`, and
`ci`, writes a summary, and stops Quark and deletes its data. Everything lives under `.flighthouse/e2e-quark/`,
which git ignores. The script is [`tool/e2e_quark/e2e.sh`](tool/e2e_quark/e2e.sh); each step is also its own target.

| Target | Step |
| --- | --- |
| `make quark-up` | download Quark `QUARK_VERSION` (checksum-verified) and start it on `PORT` with its own `HOME` |
| `make seed` | create the owner and upload `SEED_SCALE` photos and two documents; re-running uploads nothing twice |
| `make run` | build Quark's web app at `QUARK_VERSION` (cached per version), then `flighthouse collect` |
| `make report` | `flighthouse report` and `ci`; a first run with no baseline writes one first |
| `make quark-down` | stop Quark; `WIPE=1` also deletes its data and credentials |
| `make all` | all of the above, then `quark-down WIPE=1` unless `KEEP=1` |

### Prerequisites

Linux (x86_64 or arm64), Dart, `curl`, `git`, `sha256sum`, Node 22 with `npx` (Lighthouse 13.5.0 runs through
`npx`), and Chrome's shared libraries. Building the web app needs the exact Flutter version Quark's `pubspec.yaml`
pins (3.47.7 for v0.50.1) and about 90 s and 4 to 5 GB of RAM ([#139](https://github.com/autobutler-org/flighthouse/issues/139)).
The build is cached in `.flighthouse/e2e-quark/cache/web-<version>`, so only the first run per version pays for it.

### Inputs

All optional, passed as `make VAR=value` or environment variables.

| Variable | Default | Meaning |
| --- | --- | --- |
| `QUARK_VERSION` | `v0.50.1` | the Quark release tag for both the server and the web build |
| `QUARK_BIN` | downloaded | use this Quark binary instead of the release |
| `QUARK_URL` | unset | use a running Quark (with its `CREDENTIALS`); `quark-up` and `quark-down` skip |
| `QUARK_SRC` | shallow clone | a Quark checkout at `QUARK_VERSION` to build the web app from |
| `FLUTTER` | `flutter` | the Flutter binary; it must match Quark's pin |
| `PORT` | `18531` | the port the harness's Quark listens on, plain HTTP on `127.0.0.1` |
| `SEED_SCALE` | `6` | photos to seed; raise it for a bigger household in perf work |
| `KEEP` | `0` | `1` leaves Quark, its data, and its credentials in place after `make all` |
| `CREDENTIALS` | `.flighthouse/e2e-quark/credentials.env` | the owner's credentials, written once with mode 0600 |
| `BASELINE` | `.flighthouse/e2e-quark/flighthouse-baseline-<version>-scale<N>.json` | one per version and size |

The seed creates the owner without a browser. Since Quark v0.47 a client never sends a password:
`quark auth-key` derives the auth key from the password and the salt `GET /auth/salt` returns, which works for a
username that does not exist yet, so the harness calls `POST /api/v0/auth/setup` with that key. The password is
generated once and only ever stored in the credentials file.

### Reading the results

`make all` writes `.flighthouse/e2e-quark/runs/current/`:

- `summary.json`: `verdict` (`passed`, `gate-failed`, or `broken`), `exitCode`, `failedStep`, per-step exit codes
  and seconds, `scores` (0 to 1, from `report.json`), `gate` (`new`, `fixed`, `unchanged`), versions, and paths.
  Read this first.
- `report/report.html` and `report/report.json`: the full report; `report/raw/`: Lighthouse and axe output.
- `logs/<step>.log` for every step, and `logs/quark.log` for the server.

Exit codes of `make all`: `0` the gate passed, `1` the gate failed (a result: new findings or a score drop), `2`
or `3` flighthouse could not evaluate the gate (see the [quickstart](docs/quickstart-web.md#in-ci)), `10` Quark
did not start, `11` the seed failed, `12` the web build failed, `13` `collect` failed, `14` `report` failed, and
`130` interrupted. Any code other than 0 and 1 says nothing about the app.

### Common failures

- `pins Flutter 3.47.7 but FLUTTER ... is 3.47.6`: set `FLUTTER` to a binary of the pinned version, for example a
  `git clone --depth 1 -b 3.47.7 https://github.com/flutter/flutter.git` checkout.
- `something already answers on http://127.0.0.1:18531`: another Quark (often one left by `KEEP=1`) holds the
  port. Run `make quark-down`, pick another `PORT`, or set `QUARK_URL` to use it.
- The seed fails with `/auth/login -> 401`: the credentials do not belong to that Quark, usually because
  `QUARK_URL` points at an instance that was set up by someone else. Pass its `CREDENTIALS`.
- `collect` fails with `browser displayed /terms`: the sign-in steps, which are positional selectors shared with
  [`test/fixtures/quark/d8d2618e/collect.yaml`](test/fixtures/quark/d8d2618e/collect.yaml), no longer match
  Quark's screens. They work on v0.50.1.
- The gate fails after changing `SEED_SCALE` or `QUARK_VERSION` with an explicit `BASELINE`: the data on
  `/photos` changed, so the findings did. The default baseline is per version and size for this reason.
- The web build is killed: the machine ran out of memory; free some or build once on a bigger machine and copy
  `build/web` to `.flighthouse/e2e-quark/cache/web-<version>`.

### Known gaps

- The release tarball ships only the server, so the web app is still built from source at the same tag. A Quark
  release that published its web build would remove the Flutter requirement.
- macOS and Windows have no path yet; Quark's release has no binary for them, so set `QUARK_BIN`.
- The harness runs the routes of the d8d2618e configuration: `/files`, `/photos`, and `/settings/general`.
- `SEED_SCALE` only adds photos; members and channels are not seeded yet.
- Back-to-back runs on one version and size are not yet stable: a second run has failed the gate on axe
  `color-contrast` "Needs review" findings at transient `div > div:nth-child(n)` targets on `/files` and `/photos`.
  Treat a gate failure made only of those as noise until the gate tolerances cover it.

## Dart code rules (always)

### Style

- Dart, latest stable SDK, null safety, the strict analyzer modes above.
- **No comments and no emojis in code.** Names and types carry the meaning. This covers `//` and `/* */`
  everywhere. The one exception ([ADR 0018](docs/adr/0018-packaging-and-pub-dev.md)): `///` dartdoc on declarations
  exported from a package's public barrel, which pub.dev needs for full points. `///` on anything else is a finding.
- **Say it once.** When every branch of a `switch` ends with the same expression, write the branches so they
  differ only where they actually differ and move the shared part out.

### Functional core, imperative shell ([ADR 0004](docs/adr/0004-functional-core-imperative-shell.md))

- **Immutable data.** `final` fields, `const` constructors, unmodifiable collections
  (`List.unmodifiable`, `Map.unmodifiable`) at construction. No setters, no `late` mutable state.
- **Domain types are sealed classes or records** and are consumed with exhaustive `switch` expressions. No
  `default:` arm on a sealed type: adding a case must break every switch that has to handle it.
- **No inheritance hierarchies** except the one a sealed type requires. Compose functions instead.
- **Pure functions** in `model/`, `config/`, `adapters/`, `pipeline/`, and `render/`. They take data and return
  data. They never read the clock, the environment, the filesystem, or a random source; those values are passed in.
- **Side effects only in `io/` and `cli/`.** File IO, process spawning, network, browser, clock, and exit codes.
- **No mutable shared state.** No top-level or static non-final variables.

### Failure is a value ([ADR 0005](docs/adr/0005-failure-as-values.md))

- Every fallible function in the core returns `Result<T, Failure>`. It never throws and never returns `null` to
  mean failure.
- `throw` appears only for programmer errors (an `ArgumentError` on an impossible input), never for bad user
  input, bad config, or bad tool output.
- At the edge, `io/` converts exceptions from `dart:io` and subprocesses into `Failure` values with
  `on <SpecificType> catch`, never a bare `catch`.
- `Failure` is a sealed type. Each case carries enough to print a message a user can act on: which file, which
  field, which tool, what to install.

### Adapters ([ADR 0013](docs/adr/0013-adapter-contract.md))

- Adapters are the only tool-specific code. Everything after them is tool-agnostic.
- **Read the tool's real docs and real sample output before writing an adapter.** Do not guess a format. If the
  format is undocumented, say so and ask the maintainer.
- Every adapter ships with fixtures recorded from the real tool, stored under
  `test/fixtures/<tool>/<tool-version>/`, with a `SOURCE.md` saying how each was produced.
- An adapter validates its input and returns a `Failure` naming the path into the JSON that was wrong.

### Dependencies ([ADR 0017](docs/adr/0017-dependency-policy.md))

- Every dependency is listed in ADR 0017 with its justification. Adding one means updating that ADR first.
- Nothing under `lib/` of the root package depends on Flutter. Flutter-only code lives in
  `packages/flighthouse_flutter`.
- Node, Lighthouse, and axe are never dependencies of this repository. The web runner invokes them as optional
  external tools and fails with a message naming what to install.

### Tests

- Every pure function has unit tests. Every adapter has fixture tests. One end-to-end test runs the full pipeline on
  recorded fixtures and compares against a golden `report.json`.
- Tests live under `test/`, mirroring `lib/src/`.
- No mocking library. The core is pure, so tests pass data in. The shell takes its effects as function parameters
  with defaults pointing at the real implementation, so a test passes fakes.

## Pull request and commit conventions (always follow this)

- **PR titles use conventional commits:** `feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`, `perf:`.
  Lowercase, imperative: `fix: reject a negative metric value`.
- `Closes #N` goes in the PR body, not the title. In a stack, every layer carries `Closes #N`.
- Branch names reflect the issue: `feat/12-lighthouse-adapter`, `fix/31-fingerprint-route-case`.
- Fill out [the PR template](.github/pull_request_template.md).
- One focused commit per PR, signed off (`git commit -s`). This repository keeps a linear history.
- **Work with independently reviewable parts is stacked**, using the `gh-stack` skill. Step 5 of the
  `resolve-issue` skill has the triggers. A schema change goes at the bottom of the stack, the adapters and
  renderers that consume it above.
