# Phase 2 checkpoint proposal

Prepared for [#19](https://github.com/autobutler-org/flighthouse/issues/19) on 2026-10-08. This layer proposes the
decisions needed to implement the web runner. It does not accept an ADR or add a production browser dependency.

## Evidence presented

- [Browser investigation](browser-spike.md): both Dart drivers preserved all 500 axe nodes; Puppeteer downloaded
  and launched its pinned Chrome locally and in Ubuntu 24.04. Our own native macOS ARM64 probe passed with the
  default sandbox. Ubuntu's default launch failed with `No usable sandbox!`; its isolated `--no-sandbox` probe
  passed. Both successful native probes retained all 500 axe nodes. A glass-pane selector precedes the first
  frame by 204–265 ms in the ten observed quark navigations.
- [Semantics measurement](semantics-signal.md): default builds exposed zero Flutter semantics nodes. Startup
  semantics exposed 15–37 nodes; Lighthouse scored `/files` 95 and `/photos` 94 instead of the default 100.
  Axe found violations on all three routes. An actual session persisted into Lighthouse's protected routes.
- [Target comparison](../evidence/quark-targets.json): generated IDs varied on later navigation. Ancestry matched
  across the measured builds and activation modes. Blanket ordinal removal collapsed distinct actual findings.

## Decision options

| Option | Outcome | Tradeoff |
| --- | --- | --- |
| A: Dart Puppeteer, startup semantics, ancestry | Recommended. Accept 0015/0016 plus proposed 0023/0024, then implement #20–#27 in stacks. | Requires an app-side opt-in, explicit v2 baseline migration, and a supported Linux launch policy for web CI. |
| B: Dart WebDriver with the same semantics and target policy | Uses the other working Dart transport. | Requires provisioning and matching ChromeDriver in addition to Chrome, with no observed transport benefit. |
| C: Review the native launch policy before selecting a driver | Resolve the measured Ubuntu default-sandbox failure before accepting the runner. | Preserves the current package boundary while delaying production work; the isolated green probe does not establish default-policy support. |

## Proposed design

Option A follows the empirical recommendation without declaring untested platform support. The concrete config is
[ADR 0023](../adr/0023-web-runner-configuration.md): optional `web`, argv commands, a loopback SPA server, one
viewport and auth state, environment-sourced typed credentials, bounded readiness, redirect rejection, and raw
outputs consumed by the existing pipeline. The server does not provision quark or promise an API proxy.

[ADR 0024](../adr/0024-axe-target-identity.md) narrowly supersedes the axe normalization part of 0007, preserving
descendant ordinals and frame/shadow boundaries. The migration bumps fingerprints to v2; it needs explicit baseline
updates and gate tests. Root CI stays Dart-only and non-web commands never probe optional tools.

Keep the Flutter companion in phase 3 as Accepted ADR 0003 requires. The first quark opt-in can be app-side code
behind the define. Creating the companion early would require another Accepted decision change.

## Additional auth experiment

A second disposable quark 0.49.0 backend and the same semantics-enabled frontend were used for form-based auth,
separately from the original measurement's API-issued session. The real setup form created an owner, required
recovery acknowledgment and theme selection, and reached `/files`. After clearing the stored session and reloading,
the real sign-in form returned HTTP 200, reached `/files`, and stored a new session. Lighthouse attached to that
Chrome retained `/photos` and returned accessibility 94.

The same sign-in and Lighthouse transfer also succeeded using **Dart Puppeteer 3.26.0 and its pinned Chrome 152**.
The typed username and password exactly matched the intended values before submission. This extends the driver
spike's transport evidence to the real form; it is still throwaway validation, not the #22 production runner.

Earlier attempts exposed a focus race: immediate typing lost a character, including with a per-character delay.
Flutter's semantics `focus` event schedules a Flutter focus action; text-editing handlers become active on a later
semantics update. The successful experiment focused the input, awaited two animation frames, inserted the complete
text through CDP, then verified the value after the subsequent frames. The driver must await input activation and
detect a mismatch before submitting, rather than assume a typing call preserved every character. The measured
two-frame wait is not a universal guarantee for other apps or SDKs. Semantic button activation was used for form
submission; arbitrary pointer-driven app interactions remain a separate behavior to verify.

[quark-auth.json](../evidence/quark-auth.json) records the successful Node and Dart observations without secrets.
The complete Dart-driven Lighthouse output and capture source are in
[`quark-ui-auth-48a76ae`](../../test/fixtures/lighthouse/13.5.0/quark-ui-auth-48a76ae/SOURCE.md).
No setup/login secrets or recovery phrase were printed or committed.

## Implementation order after acceptance

1. Config value/parser and browser boundary (#19/#20), then dependency and bounded driver implementation (#20).
2. Build/static serve and failure cleanup (#21), then typed auth and session reuse (#22).
3. Lighthouse raw capture (#23) and pinned axe capture with ancestry (#24).
4. Axe adapter with paired fixture identity and non-collision tests (#25), and optional-tool diagnostics (#26).
5. Separate web CI with a small Flutter fixture (#27), then a complete real quark run and phase summary (#28).

Use focused signed-off commits and native merge stacks. No stack is merged as part of this task. Repository
write access is restored; publish the reviewed layers and inspect their hosted checks before merging.

## Unverified or limited

The combined core stack passed the exact Make gates in a fresh Dart-only container. The phase-2 evidence layers
passed `make check` and the existing 406-test suite. Own native macOS and Ubuntu probes checked acquisition,
launch, loopback navigation, and large axe transport; Ubuntu required an explicit sandbox-disabled probe.
These checks do not establish a full Flutter build/auth/cleanup workflow on both platforms or a supported default
Ubuntu launch policy. Reusable production auth automation, gallery coverage with populated photo data, and a
representative performance baseline remain unverified.

All four ADRs in the recommended decision are Proposed until the maintainer checkpoint accepts them. The
investigation tickets' blanket “do not start if Proposed” wording conflicts with their purpose; their acceptance
criteria should authorize empirical investigation while blocking dependent production implementation.
