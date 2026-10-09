# flighthouse

One Lighthouse-style scored report for Flutter apps, covering accessibility, performance, responsiveness, and
memory, that works as a CI gate.

> **Status: pre-release.** The pipeline reads attest, Lighthouse, and axe JSON; other sources are in progress. Progress is tracked in the
> [phase epics](https://github.com/autobutler-org/flighthouse/issues?q=is%3Aissue+label%3Aepic).

## What it does

flighthouse does not audit anything itself. It ingests the outputs of tools you may already run:

- [attest](https://pub.dev/packages/attest_cli) accessibility widget-test reports
- [Lighthouse](https://github.com/GoogleChrome/lighthouse) JSON reports
- [axe-core](https://github.com/dequelabs/axe-core) results
- `integration_test` `TimelineSummary` frame timings
- [flutter_lighthouse](https://pub.dev/packages/flutter_lighthouse) output

It normalizes them to one schema, scores them with Lighthouse's log-normal curves, diffs against a committed
baseline, and writes `report.json` and a self-contained `report.html`. In CI it fails only on new findings or on
score drops past a threshold you set.

For Flutter web apps, a `web:` config makes `collect` build the app with semantics enabled, serve it,
authenticate if configured, and run Lighthouse and axe, writing `<reportDir>/raw/lighthouse/` and
`<reportDir>/raw/axe/`. That part needs Flutter, Node, and Lighthouse, and downloads Chrome and axe-core. Everything else needs only a Dart SDK. `report`, `ci`, and `baseline` read existing
files and do not launch Chrome, Node, Lighthouse, or Flutter. Start with the
[Flutter web quickstart](docs/quickstart-web.md); [ADR 0023](docs/adr/0023-web-runner-configuration.md) specifies
`web:`.

## Install

```sh
dart pub global activate flighthouse
```

The web runner is not in a pub.dev release yet. To use it, install from the repository as the
[quickstart](docs/quickstart-web.md#prerequisites) shows.

## Usage

```sh
flighthouse collect             # copy imported raw outputs into <reportDir>/raw and run Lighthouse and axe when web is configured
flighthouse report              # write report.json and report.html
flighthouse ci                  # report, then gate against the baseline
flighthouse baseline --update   # accept the current findings and scores as the baseline
```

Exit codes: `0` passed, `1` the gate failed, `2` usage or config error, `3` unusable input or missing tool.

Today flighthouse reads attest, Lighthouse, and axe JSON. `TimelineSummary` and flutter_lighthouse adapters are
in progress.

Configuration lives in `flighthouse.yaml`. See [`example/`](example/README.md).

## Design

Decisions are recorded as ADRs in [`docs/adr/`](docs/adr/README.md).

## License

MIT. The scoring function is ported from Lighthouse (Apache-2.0); see [`NOTICE`](NOTICE).
