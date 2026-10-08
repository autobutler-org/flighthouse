# Browser automation spike

Measured for [#17](https://github.com/autobutler-org/flighthouse/issues/17) on 2026-10-08.
This is evidence for the proposed [ADR 0015](../adr/0015-browser-automation-and-axe.md), not its acceptance.
The experiment programs and their dependencies stayed outside the package. No browser dependency was added.

## Recommendation

Use Dart `puppeteer` 3.26.0 as the first driver, with an explicit Chrome download step and a bounded first-frame
wait installed before navigation. Keep `webdriver` 3.2.0 as the fallback. Both returned a large axe result intact;
Puppeteer additionally manages its matching Chrome without a separate driver process.

Require a Flutter first-frame signal followed by application readiness. The existence of a Flutter DOM host alone
does not establish either. Treat browser acquisition, launch, navigation, and script execution as separate failures.

## Download and launch

`downloadChrome` acquired Chrome for Testing 152.0.7977.42, the version pinned by Puppeteer 3.26.0. The downloaded
browser launched headlessly and rendered a test document in the session's Linux environment. A second acquisition
and launch succeeded inside an Ubuntu 24.04.5 container with a separate initially empty cache.

The minimal Ubuntu image initially failed because `unzip` was absent. Puppeteer's downloader invokes the system
executable; it is an installation prerequisite in addition to Chrome's shared libraries. Installing `unzip`,
`libnss3`, GTK, GBM, ALSA, X11/ATK libraries, and fonts resolved the failure. The container used the session proxy
and its trusted CA. Container launches used `--no-sandbox` and `--disable-dev-shm-usage`.

This session had no macOS executor and did not run a GitHub-hosted Ubuntu job. There is corroborating upstream CI:
the [v3.26.0 release commit's Build run](https://github.com/xvrh/puppeteer-dart/actions/runs/31691287237) passed
[macOS](https://github.com/xvrh/puppeteer-dart/actions/runs/31691287237/job/94418969470) and
[Ubuntu](https://github.com/xvrh/puppeteer-dart/actions/runs/31691287237/job/94418969523). Its workflow includes Chrome
acquisition and browser tests. That proves upstream's setup, not flighthouse's eventual workflow. Their Ubuntu
workflow changes AppArmor configuration; that step was not reproduced here. Verify the supported launch policy
in flighthouse's own web CI before declaring platform support.

Download once before parallel route work. The maintainer identified concurrent acquisition as a possible cause of
[a first-launch failure](https://github.com/xvrh/puppeteer-dart/issues/361#issuecomment-2568921527).

## Flutter readiness

The real quark release build at commit `48a76aea65717d9968f1608fa84c2df34a5a1d93` was served with an `index.html`
fallback and its real backend. Ten consecutive `/recover` navigations in Dart Puppeteer observed:

- One `flutter-view`, one `flt-semantics-host`, and one canvas inside the glass pane's shadow root.
- The `flutter-first-frame` event in all ten navigations.
- The view and glass pane appearing **203.7–264.8 ms before** the first-frame event.

The event is dispatched by Flutter 3.47.6's
[`platform_dispatcher.dart`](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/lib/web_ui/lib/src/engine/platform_dispatcher.dart)
on `flutter/service_worker`. Register its listener before loading the page; listening after navigation can miss it.
Wait with a timeout, then wait for any configured application selector or other application-specific readiness
condition. This is a promising signal for the measured SDK, not a stable public API guarantee across all SDKs.

`flutter-view` has ordinary child hosts in this build; the canvas is in the glass pane's shadow root. Querying only
`flutter-view.shadowRoot` incorrectly reports no canvas. The semantics host exists even when semantics is disabled.
Waiting for it cannot establish accessibility coverage. Avoid requiring zero active network requests: quark uses
persistent server-sent events. A first-frame signal and explicit app readiness are stronger conditions.

## Large axe result

Both Dart drivers navigated quark, injected the unmodified axe-core 4.11.1 script into a separate test document,
and returned `axe.run()` as Dart JSON. The document contained 500 unlabeled buttons with unique IDs.

| Driver | Matching browser | Returned JSON bytes | `button-name` nodes |
| --- | --- | ---: | ---: |
| Puppeteer 3.26.0 | Chrome 152.0.7977.42 | 1,143,573 | 500 |
| WebDriver 3.2.0 | Chrome/ChromeDriver 152.0.7977.42 | 1,143,627 | 500 |

Every returned node retained its exact `#action-N` target, HTML snippet, critical impact, and nested check arrays.
The byte counts differ because result metadata differs; they are not a byte-for-byte equivalence assertion.
WebDriver used `executeAsync` with an explicit completion callback and a 60-second script timeout. Puppeteer used
`page.evaluate` with an async function. Neither required Node to transport or execute axe. Node was used separately
to install the external script for the experiment, consistent with the proposed external-tool boundary.

Navigation timings are recorded in the evidence but are not driver benchmarks: the two probes waited for different
navigation conditions. The browser comparison did not test form typing, crash recovery, or macOS locally.

## Upstream maintenance

The [October 7 commit](https://github.com/xvrh/puppeteer-dart/commit/6f86d3654823cb6efdfdc1c18858816e43b15224)
rolls the upstream Chrome pin to 155. Recent weekly pin rolls are automated. Puppeteer 3.26.0 still pins 152; do not
silently use an arbitrary system Chrome and assume the same CDP behavior.

For the concrete [removal of old headless mode](https://github.com/xvrh/puppeteer-dart/issues/364), the maintainer
offered a fix branch two minutes after the report and the reporter confirmed it within an hour. The issue was
closed months later, so closure time alone misrepresents the initial response. The
[launch/CDP connection issue](https://github.com/xvrh/puppeteer-dart/issues/361) received same-day guidance and a
download-before-tests recommendation two days later. Conversely,
[navigation timeout issue #396](https://github.com/xvrh/puppeteer-dart/issues/396) remains open without comments.

These examples support trying the maintained Dart driver with pinned versions and our own smoke checks. They do
not establish a response SLA. No upstream messages or changes were sent.

## Evidence and remaining checks

[browser-spike.json](../evidence/browser-spike.json) records the actual download, transport, and ten first-frame
observations. The throwaway package pinned `puppeteer: 3.26.0` and `webdriver: 3.2.0` and used Dart 3.13.5.
ChromeDriver was downloaded from Chrome for Testing's public distribution for the exact matching version.

Before accepting platform support, run the download, launch, navigation, and axe smoke checks in flighthouse's own
Ubuntu and macOS jobs. Before implementing the browser abstraction, obtain the ADR checkpoint decision in #19.
