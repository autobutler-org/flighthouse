# Quark semantics signal measurement

Measured for [#18](https://github.com/autobutler-org/flighthouse/issues/18) on 2026-10-08.
The findings inform [ADR 0016](../adr/0016-semantics-enabled-web-builds.md) and the #19 checkpoint; the ADR remains
Proposed. The experiment changed only an isolated quark entrypoint and temporary Make targets, not its normal
startup or any flighthouse production code.

## Result

Enable semantics at startup for Lighthouse navigation audits. Untouched default builds expose no Flutter semantics
nodes and return misleading perfect accessibility scores. Activating the default build's placeholder enables axe
coverage, but does not make a fresh Lighthouse navigation enable semantics.

Attaching Lighthouse to the existing Chrome with `--port=9222 --disable-storage-reset` preserved quark's real
authenticated session. All six Lighthouse runs retained the requested route; none redirected to sign-in or terms.
No extra authentication headers were required.

## Measured matrix

Axe columns count **rules**, not affected nodes. Applicable Lighthouse audits have a numeric `score`, including zero;
manual and not-applicable audits are excluded. Lighthouse listed 76 accessibility audit references in each run.

| Build | Route | Semantics nodes | Axe violations | Axe passes | Axe incomplete | LH a11y | LH applicable |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Default, untouched | `/login` | 0 | 0 | 23 | 0 | 100 | 17 |
| Default, untouched | `/files` | 0 | 0 | 23 | 0 | 100 | 17 |
| Default, untouched | `/photos` | 0 | 0 | 23 | 0 | 100 | 17 |
| Startup semantics, build 1 | `/login` | 15 | 1 | 28 | 1 | 100 | 21 |
| Startup semantics, build 1 | `/files` | 37 | 3 | 28 | 2 | 95 | 21 |
| Startup semantics, build 1 | `/photos` | 32 | 2 | 25 | 2 | 94 | 20 |
| Startup semantics, build 2 | `/login` | 15 | 1 | 28 | 1 | — | — |
| Startup semantics, build 2 | `/files` | 37 | 3 | 28 | 2 | — | — |
| Startup semantics, build 2 | `/photos` | 32 | 2 | 25 | 2 | — | — |
| Default, placeholder activated | `/login` | 15 | 1 | 28 | 1 | — | — |
| Default, placeholder activated | `/files` | 37 | 3 | 28 | 2 | — | — |
| Default, placeholder activated | `/photos` | 32 | 2 | 26 | 2 | — | — |

Lighthouse was not repeated on build 2 or after placeholder activation. A dash denotes an unmeasured value. The
one-rule difference in `/photos` passes after activation is retained rather than forced into parity.

The startup-semantics axe violations were:

- `/login`: `region` (moderate), six affected nodes. Lighthouse does not score this rule, so 100 does not contradict
  the axe result.
- `/files`: `aria-command-name` (serious, one node), `nested-interactive` (serious, two nodes), and `region`
  (moderate, four nodes). Lighthouse failed `aria-command-name` and `label-content-name-mismatch`.
- `/photos`: `label` (critical, one node) and `region` (moderate, one node). Lighthouse failed `label`.

These are tool observations requiring app-level review. DOM audits still do not cover the painted canvas completely,
and enabling semantics does not replace attest or keyboard and screen-reader testing.

## Reproduction conditions

- Quark source: `48a76aea65717d9968f1608fa84c2df34a5a1d93`.
- Flutter 3.47.6, Dart 3.13.5, axe-core 4.11.1, Lighthouse 13.5.0, Chrome 151.0.7922.173, Node 24.19.0.
- Real backend: `ghcr.io/autobutler-org/quark:0.49.0`, digest
  `sha256:1c11fea80b7ae71b0f061073104d727f44326edd73d4f8754ce456dcb04ff988`, with a dedicated temporary data volume.
- `/login` signed out; `/files` and `/photos` used an actual API-issued owner session, transferred into quark's
  per-host SharedPreferences storage. This proves stored-session reuse, not form-based sign-in. That remains #22.
- Static servers used an `index.html` fallback and proxied `/api/` to the isolated backend. Ports 8770, 8771, and 8772
  served immutable default, semantics-1, and semantics-2 snapshots respectively.
- Axe viewport: 1280 × 800, dark theme. Lighthouse used its default mobile navigation configuration with only the
  accessibility category. The different viewports can produce different violations; the production configuration
  should make its viewport policy explicit.
- Readiness: a listener installed before navigation awaited `flutter-first-frame`, followed by network quiet with
  allowance for two active requests. Placeholder activation additionally awaited nonempty `flt-semantics` nodes.
- Files showed the backend's generated `groups/` and `users/` folders; photos had no seeded album or photo content.
  This does not establish gallery coverage or a representative performance benchmark.

The throwaway entrypoint called `WidgetsFlutterBinding.ensureInitialized().ensureSemantics()` when
`bool.fromEnvironment('FLIGHTHOUSE_SEMANTICS')` was true, then delegated to quark's real `main()`. The temporary
Make target invoked:

```sh
flutter build web --release --target=lib/flighthouse_main.dart \
  --dart-define=FLIGHTHOUSE_SEMANTICS=false
flutter build web --release --target=lib/flighthouse_main.dart \
  --dart-define=FLIGHTHOUSE_SEMANTICS=true
```

The semantics build was run a second time and separately snapshotted. Both produced identical `main.dart.js`
bytes (9,236,309 bytes, SHA-256 `a6f8195302cd6b559b3fe514ea4c4a79ca154894a38ab58eba6304ef885cbf6c`).
The default build was 9,236,276 bytes, SHA-256
`3f6be27f6612c29fed9ac3554662f81ccebf3f5f7ed935e144c410d66b6f78c5`. This measures these JS bundles only, not overall
download, render, or runtime cost. All three release builds succeeded, and `make check/frontend` passed with no issues.

`flutter build web --help` for the pinned SDK contains no startup semantics flag. Passing a define alone cannot
enable semantics; application code must consume it. Any permanent companion helper and quark opt-in need the
checkpoint decision before implementation.

## Targets and normalization

The first pair of semantics builds returned identical violation targets on all three routes. This is useful but
insufficient evidence that generated IDs are stable. On later navigation to the same `/files` build, IDs changed
again, and activating the default build assigned different IDs to equivalent controls. `absolutePaths: true`
retained those IDs, so it did not solve the problem.

A follow-up using axe's documented `ancestry: true` option returned ID-free ancestor paths. These paths matched
between the two builds **and** between startup and later placeholder activation on all three routes. The selectors
retain child ordinals, which distinguish repeated controls. In the actual output:

- The two `/files` `nested-interactive` nodes have different `nth-child` paths. Removing the ordinals collapses them
  into one target.
- Six `/login` `region` nodes become only two distinct ancestry paths if ordinals are removed.
- Four `/files` `region` nodes become two paths after that removal.

Do not implement blanket stripping of IDs and ordinals without a new decision: it would erase distinct findings.
The target-normalization wording in Accepted ADR 0007 needs a narrowly scoped superseding ADR. Prefer the recorded
ancestry when available, retain the ordinals inside the Flutter view, and avoid generated IDs. Keep raw selectors
for display. Structural changes can still change ancestry, and responsive layouts must use a consistent viewport.
The exact migration and fallback for imported axe output without ancestry belong in that decision and #25's tests.

## Evidence

[quark-semantics.json](../evidence/quark-semantics.json) contains all twelve measured rows and the complete target
lists from the primary run. [quark-targets.json](../evidence/quark-targets.json) contains the separate ancestry
comparison, including each affected node's original HTML and selector.

Full unmodified axe outputs with ancestry are under
[`test/fixtures/axe/4.11.1/quark-48a76ae/`](../../test/fixtures/axe/4.11.1/quark-48a76ae/SOURCE.md).
The six complete Lighthouse results are under
[`test/fixtures/lighthouse/13.5.0/quark-semantics-48a76ae/`](../../test/fixtures/lighthouse/13.5.0/quark-semantics-48a76ae/SOURCE.md).
The sources document capture options and hashes. The session's credentials were checked against every committed
output and were absent; no credentials are fixtures.
