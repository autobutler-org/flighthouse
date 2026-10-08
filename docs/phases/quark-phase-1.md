# Quark phase-1 validation

Issue #14, recorded 2026-10-08. The maintainer authorized an isolated quark test
ground. All changes remain unmerged.

The [HTML report](../reports/quark-phase-1.html) is self-contained; the
[JSON report](../reports/quark-phase-1.json) contains the same observations.
[Provenance and reproduction commands](../../test/fixtures/quark/48a76ae/SOURCE.md)
include the source commit, released backend image digest, tool versions, browser
preferences, and exact attest test.

## Results

| Category | Combined score |
| --- | ---: |
| Overall | 81 |
| Accessibility | 94 |
| Performance | 69 |
| Best practices | 81 |
| Responsiveness | Not measured |
| Memory | Not measured |

There are 71 findings: 21 serious, 10 moderate, and 40 informational. The
attest reports contain 21 observations before normalization: contrast, heading
structure, and narrow-screen focus-trap findings. These are tool findings that
need investigation, not a certification or a claim that every finding is a
confirmed user barrier.

| Browser route | Lighthouse performance | Lighthouse accessibility | Best practices |
| --- | ---: | ---: | ---: |
| `/setup` | 71 | 100 | 81 |
| `/login` | 70 | 100 | 81 |
| `/recover` | 68 | 100 | 81 |
| `/terms` | 68 | 100 | 81 |

Each requested URL matches its final displayed URL and every run has no
`runtimeError`. Setup was recorded before claiming the isolated backend;
the other routes were recorded after claiming it, signed out. This fixes the
earlier run's repeated measurement of `/terms`.

Default Flutter web semantics was not enabled. Only 17 of 76 Lighthouse
accessibility audits had scores on each page. The browser score of 100 does not
describe the painted Flutter controls, and its inclusion raises the combined
score above attest alone. Phase 2's semantics measurement remains necessary.

## Gate evidence

`collect` copied eight attest and four Lighthouse reports. `report` generated
both artifacts, `baseline --update` recorded 71 findings, and `ci` reported:

```text
0 new, 0 fixed, 71 unchanged
gate passed
```

The recorded-quark regression tests exercise the same CLI with isolated real
temporary directories:

- A fresh baseline passes with the displayed scores above.
- Adding the recorded narrow recovery screen after creating a baseline without
  it produces real new serious findings, returns exit code 1, marks the HTML
  findings as new, and leaves the baseline unchanged.
- An invalid UTF-8 input returns exit code 3, prevents gate evaluation, and
  cannot replace the previous baseline.

The collection setup exposed a separate defect: `replaceJsonFiles` deleted the
destination before copying, even when that deletion erased the configured
source. Four tests reproduced it. The lower stack layer keeps identical source
and destination directories intact and rejects a destination containing the
source, using resolved paths to account for symlink aliases.

## Validation run in this session

- flighthouse: `make check`, `make test` (415 passing tests and one Windows-only
  skip on Linux), `make test/cli`,
  and `make test/quark` pass locally.
- quark: `make build/frontend/web FLUTTER_BUILD_MODE=release`,
  `make check/frontend`, and the isolated `make test/flighthouse` harness
  (eight widget audits) pass.
- The final phase-1 stack passes `make check/pana` at 160/160 and
  `make check/publish` with zero warnings. Repository write access was restored
  after the initial capture; inspect the PR's hosted checks before merging.
- A separate [native Windows regression run](https://github.com/autobutler-org/flighthouse/actions/runs/37779354508)
  proved that the reviewed collection resolver returns an IO failure for an
  unavailable drive. The previous resolver timed out. This checks that boundary,
  not the complete quark workflow on Windows.
- The actual report was rendered at 1280x900 and 375x812: no horizontal overflow
  and no external requests.

The backend used the released 0.49.0 image while the frontend and widget tests
used source commit `48a76ae`. No macOS, Windows, authenticated browser flow,
performance variance study, or pub.dev upload was verified by this run.
