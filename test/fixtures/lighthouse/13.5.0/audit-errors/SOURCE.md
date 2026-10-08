# Lighthouse weighted audit error

Unmodified Lighthouse 13.5.0 output captured on 2026-10-08 against the real
semantics-enabled quark release build at
`48a76aea65717d9968f1608fa84c2df34a5a1d93`, Flutter 3.47.6, Dart 3.13.5,
Chrome 151.0.7922.173, dedicated quark 0.49.0 backend.

The test-only custom audit deliberately throws. Lighthouse's supported custom
audit/config API adds it to the default accessibility category at weight 1.
The exact audit and config are recorded as `.mjs.txt` source fixtures; they
stayed outside production code. No upstream code was modified or vendored.

```sh
lighthouse http://127.0.0.1:8771/files --port=9222 --disable-storage-reset \
  --only-categories=accessibility --config-path=lighthouse-error-config.mjs \
  --output=json --output-path=weighted-error.json --quiet
```

The requested/final route is `/files`. There is no top-level runtimeError,
but `flighthouse-test-audit-error` has score null and scoreDisplayMode error.
Lighthouse makes the entire positively weighted category score null.
All other normal accessibility audits remain in the full output.
Credential values were checked and absent; no fields were changed.

Contract: [Lighthouse v13.5.0 scoring.js](https://github.com/GoogleChrome/lighthouse/blob/v13.5.0/core/scoring.js)
filters zero-weight audits, then returns null when any remaining audit score
is null. Manual, informative, and not-applicable modes have their weights
zeroed by the tool. An error mode is not a not-applicable mode.

`weighted-error.json` SHA-256: `c1c3f04d80be24d002de7eae7749c366619751abb1a9568c668bd8fac0ea669b`.
