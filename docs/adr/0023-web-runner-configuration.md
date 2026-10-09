# 0023. Web runner configuration

- Status: Accepted
- Date: 2026-10-08

## Context

Phase 2 needs an optional `web:` section without making imported-output commands depend on Flutter, Chrome, or
Node. [ADR 0010](0010-configuration.md) reserves this section for a separate decision. The
[browser spike](../phases/browser-spike.md) and [quark measurement](../phases/semantics-signal.md) establish working
browser transport, startup semantics, path routing, and stored-session transfer into Lighthouse.

The experiment also exposed constraints: DOM hosts appear before the first frame; authenticated `/login` can
redirect; persistent network requests prevent a universal network-idle condition; mobile Lighthouse and desktop
axe can observe different layouts. The configuration must make those conditions explicit.

## Decision

Add `web` as an optional immutable configuration value. Absence preserves imported-output collection exactly.
Only `collect` with this section performs web work. `report`, `ci`, and `baseline` always read existing files and
never probe or acquire external tools, even when their config includes `web`.

Treat the generated axe and Lighthouse directories as configured audit inputs when `web` is present. Web-only
configs pass the shared nonempty-source guard, and imported-output commands read those directories without
invoking the runner. An empty manual-source map must not become an empty passing report in this configuration.

The initial shape is:

```yaml
app: quark
reportDir: .flighthouse
web:
  projectDir: ../quark
  build:
    command:
      - flutter
      - build
      - web
      - --release
      - --dart-define=FLIGHTHOUSE_SEMANTICS=true
    outputDir: build/web
  serve:
    port: 0
  routes:
    - /files
    - /photos
  readiness:
    timeoutSeconds: 30
    selector: '[role="main"]'
  viewport:
    width: 1280
    height: 800
    deviceScaleFactor: 1
  auth:
    url: /login
    steps:
      - type: type
        selector: 'input[aria-label="Username"]'
        valueFromEnv: FLIGHTHOUSE_USERNAME
      - type: type
        selector: 'input[aria-label="Password"]'
        valueFromEnv: FLIGHTHOUSE_PASSWORD
      - type: click
        selector: '[role="button"][aria-label="Sign in"]'
      - type: wait
        selector: '[role="main"]'
  lighthouse:
    command: [lighthouse]
  axe:
    version: 4.11.1
```

Selectors above illustrate the grammar, not a verified complete quark sign-in recipe. The application must expose
the configured readiness marker and have its host and terms setup completed. The runner does not provision a
backend, create an account, or guess an application's auth flow.

### Paths, build, and serve

- Resolve `projectDir` relative to the config file; default `.`. Resolve `outputDir` relative to that project;
  default `build/web`. Existing root config paths keep ADR 0010's behavior.
- Commands are nonempty lists of nonempty strings, passed as executable plus arguments to the existing process
  boundary. No shell parsing or environment-string expansion. The default build command is the vector above.
  Custom commands must enable startup semantics themselves; a define has no effect without app-side code.
- Bind the server to `127.0.0.1`. `port` defaults to `0`, letting the OS choose; explicitly supplied values range
  from 0 to 65535. The actual bound port forms the browser and Lighthouse URL.
- Serve files only beneath the build output directory with their MIME types. Use `index.html` for configured path
  routes and HTML navigation requests. A missing script or other static asset remains a missing-file response.
  Close the server and browser in a `finally` path after both successful and failed collection.
- Keep backend provisioning and reverse proxies outside the first runner. Quark supports bearer-token CORS and
  can be configured with an absolute backend host through its own UI. The signal experiment used an external API
  proxy; that proxy is not silently promised by the static server.

### Routes and readiness

- Require a nonempty route list. Each entry is an absolute path with optional query and fragment, not an external
  URL; reject duplicates. Preserve the requested path in the raw output filename using a deterministic hash,
  rather than treating it as a filesystem path.
- Install the first-frame listener before navigation. Apply the bounded timeout, verify a nonempty Flutter
  semantics tree, then wait for the optional application selector. Do not equate a DOM host or zero active
  network requests with application readiness.
- A requested route must remain the displayed route after readiness and in the Lighthouse result. Authentication
  or terms redirects fail collection with the requested and actual paths, rather than producing a mislabeled
  audit. Any allowed canonicalization must be documented and tested before adding it.
- The readiness selector is optional. When supplied, it is a nonempty CSS selector. `timeoutSeconds` defaults to
  30 and must be positive. Individual steps use the same timeout; do not add fixed-delay auth steps.

### Authentication and viewport

- `auth` is optional and runs once before the route list in the same browser context Lighthouse attaches to.
  `url` is an application path. Steps are a sealed union of `type`, `click`, and `wait`, with the fields shown
  above; reject fields that do not belong to that step.
- Typing reads a required nonempty named environment value at execution time. Missing values fail before any
  auth interaction. Config parsing does not read the environment. Do not put credentials in config, raw results,
  process arguments, or failure messages. Selector and step index are sufficient diagnostics.
- One run has one auth state. Public routes that redirect after sign-in belong in a separate unauthenticated
  invocation. Multiple identities, route-specific auth contexts, and scripts are deferred until a ticket requires
  them. Never silently audit the redirect target under the requested route's name.
- Use one explicit viewport for axe and Lighthouse: defaults 1280 × 800, device scale factor 1. Width and height
  are positive integers; scale factor is finite and positive. Pass matching Lighthouse screen-emulation settings
  and desktop form factor. The recorded experiment used Lighthouse's default mobile settings, so its numbers
  are evidence for semantics, not the production viewport's baseline.
- Attach Lighthouse to the driver's debugging port and disable storage reset. Inspect `runtimeError` and final
  displayed URL before accepting the output. The measured stored-session transfer worked without extra headers.

### Tools and raw output

- `lighthouse.command` defaults to `[lighthouse]`; `[npx, lighthouse]` is an explicit alternative. Probe required
  web tools only at this boundary and return actionable `MissingToolFailure` values, exit code 3.
- Use the Puppeteer dependency range prescribed by ADR 0017, starting with the tested 3.26.0 release. Acquire its
  pinned matching Chrome once before route work and record the actual browser version. Detect acquisition and
  launch prerequisites, including Linux `unzip`; do not report those failures as missing audit findings.
- `axe.version` defaults to the measured 4.11.1. Optionally accept `axe.scriptPath` for an already acquired script;
  resolve it relative to the config file. Otherwise acquire the pinned external script into the user's cache,
  inject it, and capture the actual engine version. Do not vendor upstream code.
- Run axe with `ancestry: true`, keeping the unmodified JSON result. Store per-route raw outputs beneath
  `<reportDir>/raw/axe/` and `<reportDir>/raw/lighthouse/`. See ADR 0024 for fingerprint use of ancestry.
- Reject an imported `sources.axe` or `sources.lighthouse` together with `web`, so competing writers cannot replace
  each other's raw results. Imported attest and other sources still work in the same collection.
- Collection failures remain tool/IO failures; `ci` must not turn them into a passing audit or overwrite a baseline.

### Companion package timing

Keep Accepted ADR 0003's phase-3 companion timing. Phase 2 documents and uses an app-side opt-in calling
`ensureSemantics()` behind the define; it does not add Flutter to the root workspace or create the companion early.
A reusable helper can move into `flighthouse_flutter` when phase 3 creates that package.

## Consequences

The first runner is bounded: one project, build, server, viewport, auth state, and route list. Existing raw-output
commands stay Dart-only. Configuration has source-spanned unknown-key and invalid-value failures, consistent
with ADR 0021. Browser state and installed tools remain shell concerns, not mutable core state.

The web CI fixture must demonstrate startup semantics, actual typed sign-in, a protected route, path fallback,
matching viewports, and cleanup after failures. Root CI must continue passing without Node or Flutter. Our native
macOS smoke probe passed with its default sandbox; Ubuntu's isolated sandbox-disabled probe passed after a default
launch failure. The production web workflow must demonstrate its chosen Linux launch policy and full Flutter/auth
behavior before those platforms are declared supported.

## Alternatives considered

- WebDriver: both transports worked, but it adds a separately managed matching driver process.
- A Node browser runner: unnecessary for the measured navigation and axe transport; retain it as a fallback.
- Arbitrary auth scripts, multiple sessions, and a built-in backend proxy: add broader scope than the current
  tasks require. Use application setup and separate invocations first.
- Mobile Lighthouse plus desktop axe: useful for the initial comparison but confusing as one production audit
  profile. Start with matching explicit viewports; add multiple profiles only with an explicit fingerprint decision.

## Open questions

- The final app readiness selector and quark host/terms bootstrap recipe must be demonstrated by #22.
- Ubuntu's default Chrome launch failed with `No usable sandbox!`; an explicit isolated `--no-sandbox` probe passed.
  Select the supported production/CI launch policy before #27. No host security configuration was changed in the
  native probes, and their green result does not establish default-policy Ubuntu support. Resolved by
  [ADR 0026](0026-linux-chrome-launch.md).
