# Example

A `flighthouse.yaml` for a Flutter app that produces attest and Lighthouse reports. The commands it drives are not
implemented yet; this file tracks the configuration format decided in ADR 0010.

```yaml
app: my_app
reportDir: .flighthouse
baseline: flighthouse-baseline.json
sources:
  attest:
    dir: build/attest
  lighthouse:
    dir: .flighthouse/raw/lighthouse
routes:
  patterns:
    - /files/:path(.*)
gate:
  minSeverity: minor
  maxScoreDrop: {overall: 2, perf: 5}
```

```sh
dart pub global activate flighthouse
flighthouse ci
```
