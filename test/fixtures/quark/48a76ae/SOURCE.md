# Quark phase-1 validation

Recorded on 2026-10-08 for flighthouse #14. The maintainer authorized quark as a
test ground. Changes to quark were confined to an isolated local checkout and
test backend; no changes were merged into either repository.

## Versions

| Component | Version |
| --- | --- |
| quark source | `48a76aea65717d9968f1608fa84c2df34a5a1d93` |
| quark backend image | `ghcr.io/autobutler-org/quark:0.49.0` |
| backend image digest | `sha256:1c11fea80b7ae71b0f061073104d727f44326edd73d4f8754ce456dcb04ff988` |
| Flutter / Dart | 3.47.6 / 3.13.5 |
| attest_flutter / attest | 1.5.0 / 1.11.0 |
| Node / Lighthouse | 24.19.0 / 13.5.0 |
| Chromium | 151.0.7922.173 |

The backend is a released image, not a binary compiled from the source commit.
Widget audits and the web build use the exact source commit above.

## Build and serve

Run in quark:

```sh
make build/frontend/web FLUTTER_BUILD_MODE=release
docker pull ghcr.io/autobutler-org/quark:0.49.0
make serve/docker BUILD_NAME=0.49.0 DOCKER_CONTAINER=flighthouse-quark \
  DOCKER_VOLUME=flighthouse-quark-data DOCKER_PORT=8080
```

The container uses a dedicated volume. The release build was served on
`127.0.0.1:8765` with an `index.html` fallback and `/api/` proxied to the local
backend on port 8080. The server does not alter the generated JavaScript.

Headless Chromium was launched with `--remote-debugging-port=9222`. Browser
preferences used a Quark named `Audit` at the same-origin address `/`, dark
theme, and accepted terms. The shared_preferences web values are:

```js
localStorage.setItem('flutter.hosts', JSON.stringify(JSON.stringify([
  {name: 'Audit', hostAddress: '/'}
])));
localStorage.setItem('flutter.activeHostIndex', '0');
localStorage.setItem('flutter.acceptedTermsHosts', JSON.stringify(['/']));
localStorage.setItem('flutter.themeMode', JSON.stringify('dark'));
```

This setup matters: an unclaimed backend sends `/login` to `/setup`; unaccepted
terms send other routes to `/terms`. The final URL in every recorded Lighthouse
report was checked. `/setup` was audited before creating the isolated owner
account; `/login`, `/recover`, and `/terms` were audited afterward, signed out.
No test account secrets are committed.

## Attest

The exact [widget test](attest_test.dart.txt) runs real quark pages at phone and
desktop widths. Its callbacks and existing auth probe are inert test effects.
The normal attest rules, raster contrast, and text-scale checks run unchanged.
The [attest provenance](../../attest/1.5.0/quark-48a76ae/SOURCE.md) records the
commands and the one path normalization.

## Replaying flighthouse

The committed baseline was generated with flighthouse 0.1.0 from these exact
eight attest and four Lighthouse files, without suppressions or gate overrides.
The config resolves sources relative to this directory. From flighthouse:

```sh
make test/quark
make run/cli CLI_ARGS='--config test/fixtures/quark/48a76ae/flighthouse.yaml report'
```

`make test/cli` includes this gate, so the existing Dart-only CI also validates
the quark fixtures. Node, Chrome, Flutter, and a live backend are not required
to replay the recorded run.

## Limits

- One Lighthouse run per page is a smoke test, not a performance variance study.
- Default web semantics was deliberately left off in phase 1. The browser's
  accessibility score cannot describe the canvas controls; #18 measures that.
- The widget harness audits initial states, not a running authenticated app.
- Attest's inferred passed rules retain the adapter's documented limitation:
  reports do not identify disabled rules. No rules were disabled in this run.
- Phase 1 does not measure responsiveness or memory.
