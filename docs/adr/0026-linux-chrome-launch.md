# 0026. Linux Chrome launch in web CI

- Status: Accepted
- Date: 2026-10-09

## Context

[ADR 0015](0015-browser-automation-and-axe.md) keeps Chrome's sandbox enabled for production launches and leaves the
web CI policy to this task. [ADR 0023](0023-web-runner-configuration.md) records the same open question. The
[browser spike](../phases/browser-spike.md) measured Puppeteer 3.26.0 and its pinned Chrome 152.0.7977.42.

On `ubuntu-latest`, the
[default-policy job](https://github.com/autobutler-org/flighthouse/actions/runs/37781192167/job/113324410213)
acquired that Chrome and then failed with `No usable sandbox!`. The error names Ubuntu's AppArmor restriction on
unprivileged user namespaces. An
[isolated probe](https://github.com/autobutler-org/flighthouse/actions/runs/37781506761/job/113325474391) passed only
when that job explicitly launched with `--no-sandbox`. macOS ARM64 passed with the default sandbox. No probe changed
host AppArmor, sysctl, or user-namespace policy. Upstream Puppeteer's Ubuntu workflow does change AppArmor; that
step was not reproduced and is not adopted here.

Installing the shared libraries and `unzip` that Chrome needs is still required. Those packages fix a missing-library
or unpack failure. They do not lift the AppArmor restriction, so they do not make the default sandbox work on
`ubuntu-latest`.

## Decision

- Production launches keep the sandbox on. The launcher passes Puppeteer's `noSandboxFlag: false` unless the
  explicit switch below is set. It does not honor `CHROME_FORCE_NO_SANDBOX`, and it never infers a container,
  a CI runner, or a previous failure.
- The only opt-in is the environment variable `FLIGHTHOUSE_CI_CHROME_NO_SANDBOX` set to the exact string `true`.
  Any other value, including empty, `1`, and `TRUE`, leaves the sandbox on. The variable is a CI switch for the
  GitHub `ubuntu-latest` jobs. It is not a config key and not a product default.
- `.github/workflows/web.yml` installs Chrome's host libraries on Linux, then sets that switch for the Ubuntu web
  job and the Ubuntu Chrome smoke job. The macOS smoke job does not set it. The workflow does not change AppArmor,
  sysctl, or the runner's user-namespace policy, and it does not install a distro Chrome in place of the pinned
  browser.
- A host that still cannot sandbox, and did not set the switch, fails with the existing actionable launch error.
  That error does not suggest disabling the sandbox.

## Consequences

- Ubuntu web CI can launch the pinned Chrome without copying upstream's host-security change.
- A developer machine and the macOS runner keep the default sandbox. Setting the switch locally is visible and
  deliberate.
- If `ubuntu-latest` later allows the namespace sandbox without a host-policy change, the switch can be removed
  from the Ubuntu jobs in a follow-up. Production behavior does not change when that happens.

## Alternatives considered

- Leave the sandbox on and mark Ubuntu unsupported. That drops the web workflow the phase requires.
- `chmod 4755` on the downloaded `chrome-sandbox` helper. That changes the host's privilege boundary for a binary
  the product does not install as a system package, and current Chrome for Testing still depends on the namespace
  sandbox that AppArmor blocks.
- Disable AppArmor's unprivileged user-namespace restriction for the job. That is the upstream workaround and a
  host security change. Rejected.
- A `web:` config flag. That would make a sandbox bypass part of application configuration rather than a CI-only
  switch.

## Open questions

- None. A later runner image that sandboxes without a host-policy change should retire the Ubuntu switch.
