# flutter_lighthouse output format and memory coverage

Research spike for [#34](https://github.com/autobutler-org/flighthouse/issues/34), done on 2026-10-13. It answers
the open question in epic [#29](https://github.com/autobutler-org/flighthouse/issues/29) about where memory data
comes from. [ADR 0013](../adr/0013-adapter-contract.md) listed this tool's format as "Unknown".

## Method and what was not done

- The upstream repository was shallow-cloned and read. Its only commit is `46cae07c6b831c64ce681dd32cd65b2e58cb6d45`
  (2026-06-22), which is tag `v0.1.0`. File paths below are relative to that commit.
- pub.dev metadata came from `https://pub.dev/api/packages/flutter_lighthouse` and
  `https://pub.dev/api/packages/flutter_lighthouse/score`. GitHub metadata came from `gh api` (no credentials
  beyond the existing `gh` login, nothing written upstream).
- One Flutter SDK file was read to check an assumption about image sizes (see below).
- **Nothing was run.** The tool was not built, installed, or executed. No device, emulator, or browser was used,
  and quark was not built. There is no real sample output anywhere upstream (see "Sample output"), so a real
  fixture can only come from running the tool inside a Flutter app. That was not done because of the owner's
  resource constraints.

Labels used below: **documented** means stated in the README, CHANGELOG, or a spec file upstream; **source** means
read directly from the Dart source at the commit above; **inferred** means reasoned from source but not run;
**unverified** means it could not be checked.

## 1. What it measures

flutter_lighthouse is a Flutter package (not a CLI) that runs inside the app. `Lighthouse.audit(context)` pushes
each configured named route, waits 450 ms to settle, collects for `waitPerRoute` (default 1 s), pops, and moves on
(source: `lib/src/walk/route_walker.dart:29-111`, `lib/src/core/config.dart`). Per route it collects
(documented in `README.md` "Features" and `CHANGELOG.md`; implementation from source):

| Metric | How | Source |
| --- | --- | --- |
| Frame build and raster time per frame | `SchedulerBinding.addTimingsCallback`, `FrameTiming.buildDuration` and `rasterDuration` | `lib/src/metrics/frame_collector.dart:20-38` |
| Route load latency | `DateTime.now()` from `pushNamed` to the next post-frame callback | `lib/src/walk/route_walker.dart:57-66` |
| Peak memory delta | `ProcessInfo.currentRss` sampled every 100 ms, peak minus entry, in MB | `lib/src/metrics/memory_collector.dart`, `route_walker.dart:80-87` |
| Oversized images | Flutter's `debugOnPaintImage` hook, decoded area over displayed area at or above 4x | `lib/src/metrics/image_collector.dart` |
| Widget rebuilds | Opt-in: only subtrees wrapped in `LighthouseProbe(label:)` are counted | `lib/src/metrics/rebuild_tracker.dart` |

From those it derives p50 and p95 build time, p95 raster time, average FPS (from build time only), jank ratio
(build time over 16 ms), and catastrophic frames (build time over 100 ms) (source:
`lib/src/metrics/route_metrics.dart:45-85`). It then scores each route with log-normal curves into four
sub-scores, Performance, Responsiveness, Memory, and Best Practices, and averages routes into an overall 0 to 100
score (documented: `SCORING_SPEC.md` sections 2 and 3; source: `lib/src/scoring/scoring_engine.dart`). Findings
have the ids `rebuild-storm`, `oversized-image`, `catastrophic-jank`, `jank`, `slow-route-load`, and
`memory-spike` (source: `lib/src/findings/findings_engine.dart`).

Network and bundle size are not measured in 0.1.0. The README roadmap puts them, a headless CI runner, and a
fail-on-regression threshold in v0.2 (documented: `README.md` "Roadmap", `FEATURES.md` F-CI-01 to F-CI-03).

## 2. Output format

**Status: defined in source, not documented in prose.** The README says only "Exports: JSON (CI), Markdown (PR),
HTML (shareable)". There is no schema, no field list, and no sample file. The field names below are read from the
`toJson` methods, not guessed.

The tool **does not write a file.** `ReportExporter(report).toJsonString()` returns a `String`
(`lib/src/report/exporters.dart:13-14`), pretty-printed with two-space indent. Getting it to disk is up to the
caller. The upstream example only prints a text summary with `debugPrint`
(`example/integration_test/audit_test.dart:33-55`); it never calls the JSON exporter.

Top level, from `AuditReport.toJson` (`lib/src/core/audit_report.dart:37-44`):

| Key | Type | Notes |
| --- | --- | --- |
| `overallScore` | int | `overallScore.round()`, 0 to 100 |
| `grade` | string | `Excellent` (90+), `OK` (70+), `Needs work` (50+), `Poor` |
| `coldStartMs` | int, optional | Present only when passed to `Lighthouse.score`. `Lighthouse.audit` never sets it (`lib/src/core/lighthouse.dart:24-32`) |
| `routeScores` | list | See `RouteScore` |
| `findings` | list | See `Finding` |
| `metrics` | list | See `RouteMetrics` |

`RouteScore.toJson` (`lib/src/scoring/scoring_engine.dart:63-72`):

| Key | Type |
| --- | --- |
| `routeName` | string |
| `overall` | int |
| `subScores.performance` | int |
| `subScores.responsiveness` | int |
| `subScores.memory` | int |
| `subScores.bestPractices` | int |

`Finding.toJson` (`lib/src/findings/finding.dart:35-43`):

| Key | Type | Notes |
| --- | --- | --- |
| `id` | string | One of the six ids above |
| `title` | string | Human text with the value interpolated |
| `severity` | string | `critical`, `major`, or `minor` |
| `route` | string | Route name as configured, for example `/feed`, or `(current)` |
| `metric` | string | Human text, for example `+160MB RSS`. Not a number |
| `recommendation` | string | |
| `codeExample` | string, optional | |

`RouteMetrics.toJson` (`lib/src/metrics/route_metrics.dart:94-109`):

| Key | Type | Unit |
| --- | --- | --- |
| `routeName` | string | |
| `frameCount` | int | frames |
| `p95FrameBuildMs` | double | ms |
| `p95FrameRasterMs` | double | ms |
| `avgFps` | double | fps, clamped 0 to 120, 60 when there are no frames |
| `jankRatio` | double | ratio, 0 when there are no frames |
| `catastrophicFrames` | int | frames |
| `loadLatencyMs` | double | ms, 0 for `(current)` |
| `peakMemoryDeltaMb` | double | MB of RSS growth, 0 or more |
| `oversizedImages` | list | objects with `identifier` (string), `decoded` and `displayed` (string `"<w>x<h>"`), `areaOverdraw` (double, 2 decimals) |
| `imageDecodeCount` | int | |
| `oversizedImageRatio` | double | ratio |
| `rebuildCounts` | map of string to int | Empty unless the app uses `LighthouseProbe` |
| `dwellMs` | double | ms, the configured `waitPerRoute`, not a measured time |

Things an adapter would have to cope with (source, inferred where noted):

- **No tool version in the output.** Nothing in the JSON names flutter_lighthouse or its version, so the ADR 0013
  rule that an untested major version is an `AdapterFailure` cannot be applied from the file alone. The version
  would have to come from config or the app's `pubspec.lock`.
- **"No data" and "zero" look the same.** An empty frame list gives `avgFps: 60` and `jankRatio: 0`; a platform
  without RSS gives `peakMemoryDeltaMb: 0`. The scorer treats both as perfect
  (`scoring_engine.dart:144-147`, "no signal, don't penalize").
- **Rounded scores.** Scores and `overallScore` are rounded ints; the raw doubles are not exported.

### Sample output

There is none upstream. `doc/report.png` and `doc/demo.gif` are screenshots of the in-app report screen. The only
JSON test, `test/exporters_test.dart:16-21`, checks that `overallScore` is an int and `findings` is a list. ADR 0013
requires fixtures recorded from the real tool; **running the tool inside a Flutter app is the only way to get
one**, and that was not done.

## 3. Memory and platforms

**It reports process RSS growth, not Dart heap, and only on native platforms.**

- **What is measured (source).** `MemoryCollector` reads `ProcessInfo.currentRss` from `dart:io`
  (`lib/src/metrics/memory_collector.dart:1, 30-44`). It reports the peak RSS above the value at route entry, in
  MB. RSS covers the whole process, including the engine, GPU buffers, and images, so it is not a Dart heap size.
  `FEATURES.md` F-METRIC-03 says "RSS / heap", but only RSS is implemented. Heap is not read anywhere.
- **Which platforms (source).** `_rss()` returns a value only when `Platform.isAndroid`, `isIOS`, `isMacOS`,
  `isLinux`, or `isWindows` is true, and returns 0 otherwise or on any exception.
- **Web (documented by pub.dev, behavior inferred).** pub.dev's analysis tags the package `platform:android`,
  `platform:ios`, `platform:windows`, `platform:linux`, `platform:macos`, and **not** `platform:web`. The likely
  reason is the unconditional `dart:io` import in `memory_collector.dart` (inferred). The class comment says "on
  web this collector is never constructed, the walker substitutes a no-op", but the walker constructs it
  unconditionally (`route_walker.dart:48`). So on web, if the app compiles at all, `Platform.isAndroid` throws,
  the `catch (_)` swallows it, and `peakMemoryDeltaMb` is always 0 (inferred, unverified). That 0 then scores
  the memory curve as perfect, so a web memory sub-score from this tool would be wrong, not just missing.
- **Image sizes in profile mode (source, Flutter SDK).** Flutter calls `debugOnPaintImage` inside an
  `if (!kReleaseMode)` block (`packages/flutter/lib/src/painting/decoration_image.dart` on the `stable` branch,
  read on 2026-10-13), so the oversized-image signal works in debug and profile builds but not release.

## 4. How to run it and what it needs

(Documented: `README.md` "Usage"; source and example as cited.)

- Add `flutter_lighthouse: ^0.1.0` as a dependency **of the app being audited**, then either wrap the app in
  `LighthouseOverlay` and tap a button, or call `Lighthouse.audit(context, config: ...)` from code. The example
  calls it from an `integration_test` with `flutter test integration_test/audit_test.dart -d <device>`.
- It needs a running Flutter app with a `Navigator` and **named routes**. Routes not reachable with `pushNamed`
  (for example `go_router` paths that need parameters, or sign-in-gated screens) have to be skipped or set up by
  the caller (inferred from `route_walker.dart:60-61`).
- It needs a device, emulator, or desktop build that pub.dev counts as supported. For quark, which ships only as a
  web app, there is no supported target.
- There is no CLI, no headless runner, and no file output. A CI integration has to call the exporter and move the
  string to the host itself. On web, an integration test has no filesystem, so that means passing it back through
  `integrationDriver`'s response data, the same path [ADR 0032](../adr/0032-web-frame-timing-source.md) describes
  (inferred).

## 5. License and maintenance

| Item | Value | Source |
| --- | --- | --- |
| License | MIT, copyright 2026 Jay Limbani | `LICENSE`; GitHub API `license.spdx_id` |
| Releases | One: 0.1.0, published 2026-06-22T07:43Z | pub.dev API `versions` |
| Repository history | One commit, 2026-06-22; last push the same day; one tag, `v0.1.0`; no GitHub releases | `git log`; GitHub API |
| Issues | 0 open, 0 closed | `gh issue list --state all` |
| Adoption | 0 stars, 0 pub.dev likes, 29 downloads in 30 days | GitHub API; pub.dev score API |
| pub.dev score | 160 of 160 | pub.dev score API |
| SDK constraint | Dart `^3.9.2`, Flutter `>=1.17.0` | `pubspec.yaml` |

It has not changed in almost four months, has no users visible on GitHub, and its CI features are roadmap items.

## Answers

**Can an adapter be built from documented output?** Not from documented output. The field names are fixed by the
`toJson` methods above, which is the same standing ADR 0013 gives `TimelineSummary` ("defined in source, not in
prose docs"). But three things the adapter contract needs are missing: a real sample (none exists upstream, and
recording one means running the tool in an app), a version in the output, and a way to tell "not measured" from
zero. Per AGENTS.md and ADR 0013, this is the point to stop and ask the maintainer.

**Does it answer the epic's memory question?** No, for quark. It reports process RSS growth, not heap; it is not
web-compatible according to pub.dev; and on web its memory value would be a constant 0 scored as perfect. For
native targets it gives a coarse RSS delta per route. Its frame metrics overlap what #32 already gets from
`TimelineSummary` and `watchPerformance`, with fewer fields.

## Recommendation

For the maintainer to decide:

1. **Defer #34 (recommended).** Record in the epic that memory stays "not measured" for web after phase 3, as ADR
   0032 already assumes. flutter_lighthouse adds no data quark can produce, and its one release is unmaintained.
   Revisit if a v0.2 with a headless runner and versioned file output ships.
2. **Build a native-only adapter.** Parse the `toJson` fields above, map `peakMemoryDeltaMb` to a memory
   measurement and findings by `id`, and require the version from config. This needs the owner to record a fixture
   by running the upstream example on a native target (Linux desktop is the cheapest), which this spike did not do.
   It would not help quark.
3. **Treat web memory as its own task.** If memory for quark is in scope, it needs a different source, for example
   a JS heap reading taken by the web runner's browser session. That is a new collector and a new ADR, not this
   adapter, and nothing here checked whether it works.
