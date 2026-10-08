# Source

Unmodified full results from axe-core 4.11.1 against the real quark release build
at commit `48a76aea65717d9968f1608fa84c2df34a5a1d93`, measured on 2026-10-08.
Flutter 3.47.6 startup semantics were enabled by a temporary entrypoint behind
`FLIGHTHOUSE_SEMANTICS=true`.

The browser injected the external unmodified `axe.min.js` and invoked
`axe.run(document, {ancestry: true})` at 1280 × 800, dark theme. `/login` was
signed out; `/files` and `/photos` used an API-issued session against the dedicated
quark 0.49.0 backend. This is a separate navigation from the primary counts
matrix, so generated node IDs need not match that matrix. No source data was
changed. Credential values were checked and absent.

API contract: [axe-core 4.11.1 API](https://github.com/dequelabs/axe-core/blob/v4.11.1/doc/API.md).
Axe's `target` preserves frame and shadow boundaries; `ancestry` is an optional
ID-free ancestor selector returned by the documented option. Check arrays and
all four result groups are retained, including needs-review/incomplete results.

Method and limitations: [semantics signal](../../../../../docs/phases/semantics-signal.md).

| File | SHA-256 |
| --- | --- |
| `login.json` | `594875cddea0cffdad96ab331202aa5fc7bd9e20cbcb3cc0c52d1302665d40af` |
| `files.json` | `aa44cc3050bdcd7981b6195d4fff6813c13141ea4eda7a85b907082c0ceca779` |
| `photos.json` | `9b5446cea8e603b055e114bf0bbf8eb070b37f41b26042c28be9b9f97d880b29` |
