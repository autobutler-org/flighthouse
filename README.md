# flighthouse

One Lighthouse-style scored report for Flutter apps, covering accessibility, performance, responsiveness, and
memory, that works as a CI gate.

> **Status: pre-release.** The package is scaffolded but nothing below works yet. Progress is tracked in the
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

For Flutter web apps it can also build the app with semantics enabled, serve it, and run Lighthouse and axe
against a list of routes. That part needs Node, Lighthouse, and Chrome. Everything else needs only a Dart SDK.

## Install

```sh
dart pub global activate flighthouse
```

## Planned usage

```sh
flighthouse collect             # gather raw tool outputs
flighthouse report              # write report.json and report.html
flighthouse ci                  # report, then gate against the baseline
flighthouse baseline --update   # accept the current findings as the baseline
```

Configuration lives in `flighthouse.yaml`. See [`example/`](example/README.md).

## Design

Decisions are recorded as ADRs in [`docs/adr/`](docs/adr/README.md).

## License

MIT. The scoring function is ported from Lighthouse (Apache-2.0); see [`NOTICE`](NOTICE).
