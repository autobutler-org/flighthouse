# Real quark attest reports

attest_flutter 1.5.0, attest core 1.11.0, Flutter 3.47.6, Dart 3.13.5.
Recorded on 2026-10-08 from quark commit `48a76aea65717d9968f1608fa84c2df34a5a1d93`.

Eight reports audit the real `LoginPage`, `SetupPage`, `RecoverPage`, and `TermsPage`
at 360x640 and 1280x800 with Quark's dark theme. The exact widget test is
[attest_test.dart.txt](../../../quark/48a76ae/attest_test.dart.txt). Copy it to
quark's `test/flighthouse_attest_test.dart`, add `attest_flutter: 1.5.0` as a dev
dependency, and run `flutter test test/flighthouse_attest_test.dart`.

The harness injects an unclaimed backend response using quark's existing
`authStatusProbe`, as its login tests do. It does not replace page widgets. There
are no sign-ins, network calls, or hand-written findings. The default attest
standard rules, raster contrast collection, screen-reader transcript, and text
scales 1.0, 1.3, and 2.0 are enabled. All eight widget tests passed.

Only `location.file` paths were normalized: `/workspace/quark` became
`/work/quark`, and `/workspace/.pub-cache` became `/work/pub-cache`. JSON was
indented. No findings, timestamps, labels, bounds, or fingerprints were changed.

See the [combined run provenance](../../../quark/48a76ae/SOURCE.md) for backend
and Lighthouse setup. These are one initial screen state per viewport, not an
audit of every interaction or a certification of the app.
