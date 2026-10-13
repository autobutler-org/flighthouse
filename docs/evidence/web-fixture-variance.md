# Web fixture run-to-run variance

Measured on 2026-10-13 for [#153](https://github.com/autobutler-org/flighthouse/issues/153). The data is in
[`web-fixture-variance.json`](web-fixture-variance.json).

## Recipe

```sh
make run/web-fixture
make run/web-fixture/variance RUNS=5
```

`run/web-fixture` leaves a release build of `integration/web_fixture` with semantics on. The variance target
collects that build `RUNS` times without rebuilding it, runs `report` after each collect, and writes the spread to
`build/web-fixture-variance/variance.json`, keeping each run's `report.json` under `runs/`. `RUNS` defaults to 3 so
an ordinary check stays light. These numbers used 5.

Each run audits `/public` and `/planted` with every planted defect on, at 1280 by 800. It leaves out `/account`,
so it needs no auth backend, and the performance and responsive routes, which have their own checks. A run fails
when `collect` or `report` exits nonzero. A score's failure count is the number of failed runs. A planted defect's
failure count adds the runs where its detection differs from `detectable` in
[`planted.json`](../../integration/web_fixture/planted.json).

Versions: flighthouse `7ca0437`, Lighthouse 13.5.0, axe-core 4.11.1, Chromium launched by flighthouse. The machine
was an Intel Core Ultra 7 355 with 8 CPUs, Linux, shared with other agents. Its one-minute load average after each
run was 4.5 to 6.9. Five runs took 4 minutes 5 seconds, about 49 seconds each.

## Results

5 runs, 0 failed.

| Score | Min | Median | Max | Max minus min | Failures |
| --- | --- | --- | --- | --- | --- |
| overall | 0.7818 | 0.7961 | 0.8062 | 0.0244 | 0 |
| a11y | 0.9061 | 0.9061 | 0.9061 | 0 | 0 |
| perf | 0.6490 | 0.6822 | 0.7057 | 0.0567 | 0 |
| best-practices | 0.8077 | 0.8077 | 0.8077 | 0 | 0 |
| responsiveness | null | null | null | | 0 |
| memory | null | null | null | | 0 |

| Planted defect | Detected | Expected | Failures |
| --- | --- | --- | --- |
| text field without a label | 5 of 5 | yes | 0 |
| image without alternative text | 5 of 5 | yes | 0 |
| two adjacent 8px buttons | 5 of 5 | yes | 0 |
| light gray text on white | 0 of 5 | no | 0 |
| two buttons both named Save | 0 of 5 | no | 0 |

## What the numbers say

- The accessibility and best-practices scores and every planted-defect detection were identical in all 5 runs. On
  the fixture, any change in them is a real change, not noise.
- All of the noise is in performance. Its score moved by up to 0.0567, and the overall score moved by up to 0.0244
  only because performance is part of it. A performance difference of that size between two fixture runs on this
  machine is not evidence of a change.
- Responsiveness and memory are null in every run because no web adapter emits them yet
  ([#161](https://github.com/autobutler-org/flighthouse/issues/161)), so they have no spread to measure.
- Five runs on a shared machine bound the spread from below. They do not set a gate tolerance, and they say nothing
  about quark, whose variance is in [`quark-variance.md`](quark-variance.md).
