# 0015. Browser automation and axe

- Status: Proposed, pending the phase 2 spike
- Date: 2026-10-06

## Context

The web runner has to open pages, wait for Flutter to render, sometimes click (the semantics placeholder, a login
form), and run axe in the page. The brief says to look at the Dart ecosystem first and fall back to Node tooling
behind a small interface if nothing is adequate.

Candidates, checked on pub.dev and GitHub on 2026-10-06:

| Option                    | Latest, published       | Repo activity          | Notes                                              |
| ------------------------- | ----------------------- | ---------------------- | -------------------------------------------------- |
| `puppeteer` (Dart port)   | 3.26.0, 2026-08-13      | pushed 2026-09-30, 52 open issues | Chrome DevTools Protocol. Can download a pinned Chrome. `page.evaluate` runs arbitrary JS and returns JSON. |
| `webdriver` (Dart team)   | 3.2.0, 2026-09-09       | pushed 2026-10-01, 27 open issues | W3C WebDriver. Needs a separate chromedriver process matching the Chrome version. |
| Node: Playwright or `@axe-core/cli` | n/a           | n/a                    | The fallback the brief allows, as a subprocess.    |

axe-core is a single JavaScript file (`axe.min.js`, MPL-2.0) that runs in the page. With either Dart driver it can be
injected and `axe.run()` evaluated, with no Node involved at runtime.

## Decision (proposed)

- Define a small interface in `io/`: open a URL, wait for a selector, click, type, evaluate a script returning JSON,
  close. The web runner depends only on it.
- First implementation: `package:puppeteer`, because it needs no extra driver process and can fetch its own Chrome.
- axe-core is not vendored into the repository. The runner loads `axe.min.js` from a path in config or downloads a
  pinned version into a cache directory, then injects it and calls `axe.run()`.
- If the spike shows puppeteer cannot do what we need, the next choice is `webdriver`, then a Node subprocess behind
  the same interface.

## Spike before accepting

The first phase 2 task answers these and reports back before this ADR is accepted:

1. Does puppeteer's Chrome download and headless launch work on `ubuntu-latest` and macOS?
2. Can it wait for Flutter's first frame reliably (a selector on `flt-glass-pane` or the semantics host)?
3. Does injecting `axe.min.js` and returning `axe.run()` results round-trip intact for a large page?
4. How responsive are the maintainers? Look at recent issues and fixed bugs for CDP version drift.

## Spike evidence

The [2026-10-08 investigation](../phases/browser-spike.md) recommends Puppeteer 3.26.0. Both Dart drivers preserved
a 500-node axe result, and Chrome download and launch succeeded locally and in Ubuntu 24.04. The exact release's
upstream CI provides Ubuntu and macOS corroboration. Our own native macOS ARM64 acquisition, default-sandbox launch,
navigation, and 500-node axe probe also passed. Our Ubuntu job acquired Chrome but its default launch failed with
`No usable sandbox!`; the supported Linux launch policy remains a checkpoint requirement.
A second isolated Ubuntu probe passed with `--no-sandbox`, while macOS passed again with its default sandbox.
These results are recorded separately and do not imply default-sandbox support on that Ubuntu runner.

Ten quark navigations showed that the glass pane and semantics host precede the first frame. Install a
`flutter-first-frame` listener before navigation, apply a timeout, and follow it with application readiness.
Chrome acquisition requires `unzip` on Linux and should happen before parallel route work. These findings inform
the proposal; this ADR remains Proposed until the #19 maintainer checkpoint.
