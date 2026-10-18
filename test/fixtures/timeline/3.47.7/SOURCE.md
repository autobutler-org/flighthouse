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
