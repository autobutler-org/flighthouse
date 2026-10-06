# 0016. Semantics-enabled Flutter web builds

- Status: Proposed, pending the phase 2 signal measurement
- Date: 2026-10-06

## Context

Flutter web paints to a canvas. Assistive technology and DOM-based auditors (axe, Lighthouse's accessibility
audits) see Flutter's accessibility tree only once semantics is enabled, when Flutter mirrors its semantics tree into
the DOM. By default that happens only after the user activates the hidden "Enable accessibility" placeholder, or when
the app calls `SemanticsBinding.instance.ensureSemantics()`.

Expected consequences, to be measured rather than assumed:

- Lighthouse in navigation mode loads the page itself and cannot click the placeholder, so against a default build
  its accessibility audits should see almost nothing.
- axe driven through our own browser can click the placeholder first, so it may get signal from a default build.

quark specifics that affect the runner:

- Most quark routes require sign-in (`_authRedirect` in `lib/router.dart`). Only routes such as `/login`, `/setup`,
  and `/terms` are public. The runner needs a login step, and Lighthouse needs the session.
- quark uses `PathUrlStrategy`, so routes are plain paths, and the dev server and the built app both need to serve
  `index.html` for unknown paths.

## Decision (proposed)

- **Measure before building.** The first web task builds quark twice, default and semantics-enabled, and for three
  routes (`/login`, `/files`, `/photos`) records the axe violation, pass, and incomplete counts, and Lighthouse's
  accessibility score and number of applicable audits. The numbers go back to the maintainer before more web work.
- If semantics has to be on at load, the supported way is an app-side opt-in behind a define, for example
  `--dart-define=FLIGHTHOUSE_SEMANTICS=true`, with a one-line helper in `flighthouse_flutter` that calls
  `ensureSemantics()` when it is set. The runner passes the define when it builds.
- Lighthouse gets the session by attaching to the runner's Chrome (`--port`) with storage reset disabled, after the
  runner has signed in. If that does not work, the fallback is passing the session through `--extra-headers`.
- The runner's config (`web:` section) gets its own ADR after the measurement, covering the build command, serve
  port, routes, and auth steps.

## Open questions

- Is an app-side opt-in acceptable for quark, given that it is a change to quark itself?
- Whether `flutter build web` offers any flag that enables semantics at startup is to be verified against the
  Flutter version quark pins (3.47.6). None is assumed here.
