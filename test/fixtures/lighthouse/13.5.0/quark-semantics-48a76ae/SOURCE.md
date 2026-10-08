# Source

Six unmodified Lighthouse 13.5.0 results against real quark commit
`48a76aea65717d9968f1608fa84c2df34a5a1d93`, captured on 2026-10-08.
Flutter 3.47.6 release builds differed only in the isolated entrypoint's
`FLIGHTHOUSE_SEMANTICS` define. `default-*` used false at port 8770;
`semantics-1-*` used true at port 8771. Each server proxied the same isolated
quark 0.49.0 backend and served `index.html` for path routes.

```sh
lighthouse http://127.0.0.1:PORT/ROUTE --port=9222 --disable-storage-reset \
  --only-categories=accessibility --output=json --output-path=OUTPUT --quiet
```

Chrome 151.0.7922.173, Node 24.19.0; default Lighthouse mobile navigation
settings. `/login` was signed out. `/files` and `/photos` reused a real
API-issued session in localStorage. Every `finalDisplayedUrl` matched the
requested route. No runtime error was reported. The outputs retain all audits,
including manual and not-applicable results. No fields were removed or changed.
Credential values were checked and absent.

Method, scores, and limitations: [semantics signal](../../../../../docs/phases/semantics-signal.md).

| File | SHA-256 |
| --- | --- |
| `default-login.json` | `9f7e007690933836ec4760732e2f99c627fe8dadaf6a3ee58a69293a2c7e7803` |
| `default-files.json` | `5fe83cec36305ecf3c24041762bf6797f308f145606337ca760f6be8ca5941b4` |
| `default-photos.json` | `f3bf11131f8254bdb976baf6aaf1792624b4779d660bc205176f94ab52ac8034` |
| `semantics-1-login.json` | `abb56e2817af6a8602a37ab875116fba9eb0699264685bc18062b04ca18a0066` |
| `semantics-1-files.json` | `864829005efab5244d99fa4395ddac9587ac65275b2dbbce2a76e8b82c921c70` |
| `semantics-1-photos.json` | `10892ad84f373c501efe63e0f7e1bc26a1a33597f674d2408f9adc7c8de91276` |
