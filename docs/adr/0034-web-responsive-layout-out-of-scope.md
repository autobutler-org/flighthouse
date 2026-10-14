# 0034. Web responsive layout is out of scope

- Status: Accepted by delegated Opus review, 2026-10-13; maintainer may revert
- Date: 2026-10-13

## Context

[#161](https://github.com/autobutler-org/flighthouse/issues/161), found by the responsive fixture routes (#152):
flighthouse reports nothing when a Flutter web layout overflows at a narrow viewport. The evidence, and where it was
read:

- **The recorded run.** `integration/web_fixture/responsive.json` holds `/responsive/control` (six 112px cards in a
  `Wrap`) and `/responsive/overflow` (the same cards in a `Row`, 712px wide). Collected at 1280x800 and 360x800 with
  Lighthouse 13.5.0 and axe 4.11.1, both routes have a `responsiveness` score of `null` and zero `responsiveness`
  findings at both widths. `integration/web_fixture/tool/check_responsive.py` measures the narrow minus wide
  difference in `responsiveness` findings on the overflowing route: 0.
- **No tool we drive reports it.** The Lighthouse adapter maps only `performance`, `accessibility`, and
  `best-practices`. Lighthouse 13 has no `content-width` audit, and the page could not trip one anyway: Flutter sizes
  its canvas to the viewport, so the document never scrolls horizontally. axe has no overflow rule.
- **The one difference is incidental.** At 360px the overflowing route's a11y findings drop from 6 to 3. The `Row`
  sits in a `Center` (`integration/web_fixture/lib/main.dart`, `OverflowPage` and `_Main`), so at 360px cards 1 to 3
  span 0 to 352px and cards 4 to 6 start at 360px or later, entirely off screen. Three of six cards vanish and three
  findings vanish.
- **Flutter clips semantics rects.** In the Flutter 3.47.7 SDK, `_SemanticsGeometry` in
  `packages/flutter/lib/src/rendering/object.dart` intersects each node's rect with its ancestors' semantics and paint
  clip rects, and `shouldDrop` drops a node whose rect is then empty (`SemanticsNode.isInvisible` in
  `semantics/semantics.dart`). A partly visible node keeps only its visible part. This was read, not traced through
  the web engine; it agrees with the 6 to 3 drop.
- **Flutter reports overflow only in debug builds.** `RenderFlex.paint` (`rendering/flex.dart`) calls
  `paintOverflowIndicator` inside an `assert`, and `DebugOverflowIndicatorMixin._reportOverflow`
  (`rendering/debug_overflow_indicator.dart`) is what emits "A RenderFlex overflowed by N pixels on the right".
  Assertions are compiled out of profile and release builds, so a profile build, which #161 suggests, reports
  nothing. `flutter build web --debug` exists in 3.47.7. The report is a `FlutterError` passed to
  `FlutterError.reportError`; there is no dedicated overflow error type, so code recognizes one only by its text.
- **Widget tests already fail on overflow.** `flutter_test`'s binding installs its own `FlutterError.onError`, and a
  widget test fails when a `FlutterError` is reported during it; the overflow report is one. A test that pumps a screen at a phone-sized surface catches the
  defect without a browser.
- **`responsiveness` already means something else here.** [Epic 03](../epics/03-frame-timing-and-flutter-lighthouse.md)
  scores the `responsiveness` category from frame timing, in line with Lighthouse, where responsiveness means input
  latency. Layout reflow is a different property that shares the English word.
- **The project brief limits what flighthouse does itself.** [ADR 0002](0002-aggregate-existing-tools.md):
  flighthouse ingests other tools' output and does not audit anything itself. [ADR 0023](0023-web-runner-configuration.md)
  fixes one viewport per run and adds more only with an explicit fingerprint decision.

## Decision

- flighthouse does not report web layout overflow, and no web finding maps to `Category.responsiveness`. A null
  `responsiveness` score on a web-only run is expected, not a defect.
- The README and the web runner docs say so, and point to widget tests at narrow surface sizes as the place Flutter
  already catches overflow.
- `integration/web_fixture/responsive.json` keeps both routes and its recorded difference of 0 as a guard. Its `gap`
  link points to this ADR instead of #161, and `check_responsive.py` keeps failing if flighthouse ever reports the
  routes differently, so a layout signal cannot arrive without a new ADR.
- If a web layout signal is wanted later, Option B below is the starting point, in a new ADR that supersedes this one.

## Options

### A. Semantics nodes whose bounds fall outside the viewport

The runner reads the `flt-semantics` DOM rects after load and emits a finding for each node outside the viewport.

- For: uses the browser and semantics build the runner already has; no new build.
- Against: Flutter clips semantics rects to their visible part and drops nodes clipped away, so on the fixture the
  off-screen cards are not in the tree to measure. The signal is absent exactly where the defect is. It would also be
  a check flighthouse evaluates itself, against ADR 0002.
- Verdict: rejected on the evidence above. A one-route measurement could confirm it, but no reading of the SDK
  suggests it would fire.

### B. Flutter's own overflow reports from a debug build

The runner builds a third time with `flutter build web --debug`, serves it at each configured viewport, and collects
overflow reports. App-side code (as [ADR 0016](0016-semantics-enabled-web-builds.md) does for semantics) or a
`flighthouse_flutter` helper hooks `FlutterError.onError` and writes each overflow as structured JSON, which an adapter
maps to findings.

- For: Flutter is the auditor, so ADR 0002 holds. It names the widget and the pixel count, the exact defect.
- Against: a debug build is a different compile from what ships, and slower to build and load; it adds a build and a
  pass per viewport to every web run. It needs code in the target app, as quark's semantics opt-in did. Overflow is
  recognized only by the `FlutterError` message text, which Flutter does not document as a format, so the adapter's
  fixtures must be re-recorded per Flutter version. Several viewports per run need the fingerprint decision ADR 0023
  deferred, and the category question below.
- Verdict: the best of the signals, at a cost not yet justified while widget tests catch the same defect.

### C. Viewport-sweep diff of a11y findings or semantics nodes

The runner collects at two viewports, and the pipeline reports content present at the wide one and gone at the
narrow one. The fixture already shows a difference of 3.

- For: no new tool and no new build; the data exists today.
- Against: the signal is any content that disappears, not overflow. A responsive app that collapses a navigation
  rail into a drawer, or shows fewer grid columns, at a narrow width triggers it, so it penalizes the layouts it
  should reward. On the fixture it works only because each card happens to carry an a11y finding. It needs
  multi-viewport runs and a new kind of finding computed by flighthouse, against ADR 0002.
- Verdict: rejected; the false positives land on correctly responsive apps.

### D. Out of scope (chosen)

- For: no new build, no app-side code, no new adapter, no fragile text matching. Keeps `responsiveness` meaning one
  thing. The defect is caught by widget tests, which Flutter already supports.
- Against: a web-only app without narrow-surface widget tests, quark today, gets no overflow coverage from
  flighthouse. #161's first "done when" (a nonzero difference) is not met; its alternative is.

## Consequences

- #161 closes on acceptance of this ADR plus a follow-up that updates the README, the `gap` link in
  `responsive.json`, and the failure message in `check_responsive.py`. That follow-up is docs and fixture metadata
  only.
- Quark's overflow coverage, if wanted, is widget tests in quark at phone sizes, outside this repository.
- Revisiting means Option B in a new ADR, which must also decide the category and the multi-viewport fingerprint.

## Open questions

- If Option B is ever taken, which category does a layout finding belong to? Not `responsiveness`, per the above;
  `best-practices` or a new category are the candidates, and a new category changes the schema in
  [ADR 0006](0006-core-schema.md) and the weights in [ADR 0008](0008-scoring.md).
- Should the `flighthouse_flutter` companion offer a widget-test helper that pumps a screen at several surface sizes?
  That would be a test convenience, not a report signal, and is not part of this decision.
