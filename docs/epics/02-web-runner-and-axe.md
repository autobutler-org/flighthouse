# [EPIC] Phase 2: Flutter web runner and axe adapter

**Model scope: Opus.** It starts with two empirical investigations whose results decide the design.

## Goal

`flighthouse collect` builds a Flutter web app with semantics enabled, serves it, signs in if configured, and runs
Lighthouse and axe against a configured list of routes, writing raw outputs the adapters read. When Node, Lighthouse,
or Chrome is missing, it fails with a message naming what to install, and every non-web command still works.

## ADRs

0014 Accepted before task 3. 0015 and 0016 are accepted after tasks 1 and 2 report back. A new ADR for the `web:`
config section is written after task 2.

## Tasks

1. **Spike: browser automation.** Answer the four questions in ADR 0015 for `package:puppeteer`, with `webdriver` as
   the comparison. Report findings before choosing. Throwaway code, not merged.
   **Model scope: Opus.** Evaluation and recommendation.
2. **Measure: semantics signal.** Per ADR 0016, build quark default and semantics-enabled, run axe and Lighthouse on
   `/login`, `/files`, `/photos`, and report counts and scores. Also compare axe targets across two builds of the
   same commit, to settle ADR 0007's target normalization.
   **Model scope: Opus.** The result decides whether to invest further.
3. **Checkpoint.** Present tasks 1 and 2, get ADRs 0015 and 0016 accepted, write the `web:` config ADR.
   **Model scope: Opus.** Design decision.
4. **Browser interface and implementation.** The `io/` interface from ADR 0015 and its first implementation.
   **Model scope: Opus.**
5. **Build and serve.** Run `flutter build web` with the configured defines, serve `build/web` from a `dart:io`
   static server with an `index.html` fallback for path URLs.
   **Model scope: Opus.**
6. **Auth step.** Configured sign-in steps run in the browser before the route list, and the session carries into
   Lighthouse.
   **Model scope: Opus.** Depends on how Lighthouse attaches, which task 2 will have explored.
7. **Lighthouse runner.** Subprocess per route, attached to the runner's Chrome, raw LHR written to
   `<reportDir>/raw/lighthouse/`.
   **Model scope: Opus.**
8. **axe runner.** Fetch a pinned `axe.min.js` into a cache, inject it, run `axe.run()` per route, write raw results.
   **Model scope: Opus.**
9. **axe adapter.** Docs first from axe-core's API docs, fixtures from task 8 output, target normalizer per ADR 0007.
   **Model scope: Opus.**
10. **Missing-tool messages.** Detection and `MissingToolFailure` for Node, Lighthouse, and Chrome, with tests that
    non-web commands never probe for them.
    **Model scope: Sonnet.** Fully specified by ADR 0014.
11. **Web CI workflow.** `.github/workflows/web.yml` with a small Flutter web fixture app, the only workflow with Node.
    **Model scope: Opus.** Cross-tool CI setup.
12. **Run against quark and summarize.** Real report including authenticated routes; phase summary.
    **Model scope: Opus.**

## Exit criteria

- `flighthouse collect && flighthouse ci` works on quark, authenticated routes included.
- The main CI workflow still has no Node.
