# Example

A working `flighthouse.yaml` for a Flutter app. It configures attest reports and imported Lighthouse JSON.

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
flighthouse collect             # copy each source's raw outputs into <reportDir>/raw
flighthouse report              # write report.json and report.html
flighthouse ci                  # report, then gate against the baseline
flighthouse baseline --update   # accept the current findings and scores as the baseline
```

An optional `web:` section is specified in
[`docs/adr/0023-web-runner-configuration.md`](../docs/adr/0023-web-runner-configuration.md).
