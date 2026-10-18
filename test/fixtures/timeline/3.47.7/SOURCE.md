# Flutter 3.47.7 frame timing summaries

`perf-control.frame_timing_summary.json` and `perf-janky.frame_timing_summary.json` are the `timeline` artifact of
the Record timeline workflow (`.github/workflows/record-timeline.yml`), run
<https://github.com/autobutler-org/flighthouse/actions/runs/39095245787>, recorded on 2026-10-18. They are
committed exactly as downloaded with
`gh run download 39095245787 --name timeline --dir test/fixtures/timeline/3.47.7`.

The run executed this from `integration/web_fixture` on the `web-server` device, with chromedriver listening on
port 4444:

```sh
flutter drive -v -d web-server --browser-name=chrome --headless \
  --driver=test_driver/perf_test.dart \
  --target=integration_test/perf_test.dart
```

Versions printed in the run log:

- Flutter 3.47.7, channel stable, framework revision `abaf9c5237`, engine revision `deb287481e`
- Dart 3.13.5
- Google Chrome 155.0.8059.39
- ChromeDriver 155.0.8059.39

The control report covers 2 frames with an average build time of 18.3 ms and 1 missed build budget. The janky
report covers 17 frames with an average build time of 124.494 ms and 17 missed build budgets.

## Format, checked against

Flutter 3.47.7, framework revision `abaf9c5237`, as read for [ADR 0032](../../../../docs/adr/0032-web-frame-timing-source.md):

- `packages/flutter_test/lib/src/frame_timing_summarizer.dart` (`FrameTimingSummarizer.summary`, its keys and units,
  and the 16 ms `kBuildBudget` both missed-budget counts are taken against)
- `packages/integration_test/lib/integration_test.dart` (`watchPerformance` and its `reportKey`)

Both recordings hold exactly the same 31 keys. The GC counts are `-1`, not `0`, and every layer and picture cache
value is `0`, which answers ADR 0032's open question for this web build in Chrome 155.

## Mapping

| summary                                                     | flighthouse                                                   |
| ----------------------------------------------------------- | ------------------------------------------------------------- |
| file name `<scenario>.frame_timing_summary.json`            | the scenario is the route                                     |
| tool version                                                | `unknown`: the summary carries none, so any key outside the 31 above is refused instead |
| average, 90th, 99th percentile, worst frame build and rasterizer time | `responsiveness` measurements in `ms`, weight 1, named by their key, scored only with configured control points |
| `missed_frame_build_budget_count`, `missed_frame_rasterizer_budget_count` | `responsiveness` measurements in `count`, weight 1 |
| `frame_count`, `frame_build_times`, `frame_rasterizer_times` | validated; `frame_count` appears in finding messages          |
| GC counts and layer and picture cache values                | validated, not measured (ADR 0032)                            |
| `<scenario>.timeline_summary.json`                          | refused until a real `TimelineSummary` fixture is recorded   |
| any other file name                                         | refused, naming the file                                      |

Each phase, build (`frame-build-budget`) and raster (`frame-rasterizer-budget`), is at most one finding, with no
target and the phase's average time as its metric:

| average time for the phase      | severity   |
| ------------------------------- | ---------- |
| over 4 budgets (64 ms, < 15 fps) | critical  |
| over 2 budgets (32 ms, < 30 fps) | serious   |
| over 1 budget (16 ms, < 60 fps)  | moderate  |
| within budget, some frames missed | minor    |
| within budget, no frames missed | no finding |

The control yields two moderate findings. The janky recording yields a critical build finding and a minor raster
finding.
