# Source

Complete unmodified Lighthouse 13.5.0 output after real quark form-based
sign-in driven by Dart Puppeteer 3.26.0 / Chrome 152.0.7977.42, on 2026-10-08.
Frontend source: `48a76aea65717d9968f1608fa84c2df34a5a1d93`, Flutter 3.47.6,
Dart 3.13.5, release build with the isolated startup-semantics opt-in.
Backend: quark 0.49.0 on a second disposable data volume.

The real setup form first provisioned the test owner. Its session was cleared;
Dart then entered the actual username/password, submitted sign-in, checked
HTTP 200, reached `/files`, and verified session storage. Lighthouse attached
to that same browser's debugging port with storage reset disabled and
audited `http://127.0.0.1:8773/photos`. The final URL remained `/photos`;
no runtime error was reported. Capture used `--only-categories=accessibility`
and default Lighthouse mobile settings. The library contained no photos.

No fields were modified or omitted. All known task-created credentials were
checked against the output and absent.

Method and focus-race limitations: [checkpoint](../../../../../docs/phases/web-checkpoint.md).

`photos.json` SHA-256: `910a21e71600dd6d8a10f769949505054196b93c8eb3eb9b673ef08b5711de36`.
