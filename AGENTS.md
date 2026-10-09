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
