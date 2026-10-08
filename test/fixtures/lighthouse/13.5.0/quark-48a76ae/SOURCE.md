# Real quark Lighthouse reports

Lighthouse 13.5.0, Node 24.19.0, Chromium 151.0.7922.173, Flutter 3.47.6.
Recorded on 2026-10-08 from the release web build of quark commit
`48a76aea65717d9968f1608fa84c2df34a5a1d93`.

The four files are the complete, unchanged JSON from real Lighthouse CLI runs.
Each requested URL matches its `finalDisplayedUrl`: `/setup`, `/login`,
`/recover`, and `/terms`. There is no `runtimeError` in any report.

For each route, after seeding the browser with a local Quark host and accepting
its terms:

```sh
lighthouse http://127.0.0.1:8765/<route> --port=9222 --disable-storage-reset \
  --only-categories=accessibility,performance,best-practices \
  --output=json --output-path=<route>.json --quiet
```

Mobile simulation and Lighthouse's default throttling were used. Semantics was
not enabled. Accessibility is 100 in all four files, but only 17 of the 76
category audits have a score; Flutter's painted controls are absent from the
DOM. This is not evidence that those controls pass accessibility checks.

`setup.json` was recorded with an unclaimed, isolated backend. The backend was
then claimed by a temporary test account so `/login` stayed on the login page.
The other three audits were signed out. No credentials or session tokens are
present in these fixtures.

See the [combined run provenance](../../../quark/48a76ae/SOURCE.md) for the
backend, static server, and browser preparation.
