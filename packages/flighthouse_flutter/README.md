# flighthouse_flutter

Flutter test helpers for [flighthouse](https://pub.dev/packages/flighthouse), the Lighthouse-style scored report
and CI gate for Flutter apps.

> **Status: pre-release.** This package is a scaffold and exports no API yet. Helpers that write
> `integration_test` `TimelineSummary` results where `flighthouse collect` reads them are tracked in the
> [phase 3 epic](https://github.com/autobutler-org/flighthouse/issues/29).

The `flighthouse` CLI itself depends on no Flutter package. Flutter-only helpers live here so that
`dart pub global activate flighthouse` stays Flutter-free.

## Install

```sh
flutter pub add --dev flighthouse_flutter
```

## License

MIT. See [LICENSE](LICENSE).
