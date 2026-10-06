# Lighthouse 13.5.0 fixtures

Real Lighthouse reports (LHR JSON), recorded on 2026-10-06 and not edited.

| File                 | Page                                                                   |
| -------------------- | ---------------------------------------------------------------------- |
| `quark-login.json`   | autobutler-org/quark's default (no semantics) Flutter web build from 2026-10-05, served locally with an `index.html` fallback, requested at `/login`. The app redirected client-side to `/terms`, since no backend was running. |
| `a11y-failures.json` | `a11y-failures.page.html`, a deliberately inaccessible page served with `python3 -m http.server` |

Command, with Chromium 152.0.7977.82 headless:

```sh
CHROME_PATH=/usr/bin/chromium npx -y lighthouse@13.5.0 http://127.0.0.1:<port>/<route> \
  --output=json --output-path=<file> \
  --chrome-flags="--headless=new --no-sandbox" --disable-full-page-screenshot --quiet
```

`--disable-full-page-screenshot` only omits the base64 page screenshot, which the adapter doesn't read.

## Format, checked against

- `types/lhr/lhr.d.ts` and `types/lhr/audit-result.d.ts` in GoogleChrome/lighthouse `main`
- `core/config/default-config.js` for category membership and audit weights

## Mapping

| Lighthouse                                 | flighthouse                                             |
| ------------------------------------------ | ------------------------------------------------------- |
| `performance`, `accessibility`, `best-practices` | `perf`, `a11y`, `best-practices`                  |
| `seo`, `agentic-browsing`, other categories | ignored                                                |
| `binary` audit                             | `RuleOutcome`, weight from `auditRefs`, passed when score is at least 0.9 |
| `numeric`, `metricSavings` audit           | `Measurement`, weight from `auditRefs`, `toolScore` is the audit score |
| `manual`, `informative`, `notApplicable`, `error`, or a null score | skipped, as Lighthouse ignores them |
| audit score below 0.9                      | a `Finding`, one per `table` row with a `node.selector`, otherwise one with no target |
| `numericUnit` `millisecond`, `byte`, `element`, `unitless` | `ms`, `bytes`, `count`, `ratio`; any other unit is a failure |
| route                                      | `requestedUrl`, falling back to `finalDisplayedUrl`     |

Severity of a failing binary audit, inverting Lighthouse's accessibility weight table:

| Weight      | Severity |
| ----------- | -------- |
| 10 or more  | critical |
| 7 to 9      | serious  |
| 3 to 6      | moderate |
| above 0     | minor    |
| 0           | info     |

A failing measured audit is `serious` below 0.5 and `moderate` from 0.5 to 0.9, or `info` when its weight is 0.

## What these fixtures show

- Scoring the adapter's output reproduces every Lighthouse category score in both files, exactly after Lighthouse's
  rounding to two decimals.
- On the default quark build, 49 of 76 accessibility audits were not applicable and the accessibility score was
  1.0. The canvas exposes almost nothing to the DOM, which is the phase 2 semantics problem (ADR 0016).
