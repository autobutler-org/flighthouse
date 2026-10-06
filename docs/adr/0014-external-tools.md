# 0014. External tools are optional subprocesses

- Status: Accepted
- Date: 2026-10-06

## Context

This is a Dart project end to end; Node is not part of the codebase. Lighthouse and axe are Node-ecosystem tools.
Everything except the web runner must work without Node.

## Decision

- Lighthouse is invoked as an external CLI: `lighthouse` on `PATH`, or the command in `web.lighthouse.command`
  (for example `npx lighthouse`). Output is `--output=json`.
- Before a web run, `io/` checks each required tool (`lighthouse --version`, a Chrome binary) and returns a
  `MissingToolFailure` naming the tool and how to install it, for example
  `Lighthouse not found. Install it with: npm install -g lighthouse`. Exit code `3`.
- The check runs only for commands that need the tool. `report`, `ci`, and `baseline` over existing raw files never
  look for Node, Lighthouse, Chrome, or axe.
- Process spawning goes through one function type in `io/`, so tests pass a fake.
- Tool versions are captured from the tool and recorded in `ReportMetadata.toolVersions`.
- CI proves the separation: the main workflow runs in a Dart-only container that has no Node, and the web runner has
  its own workflow ([ADR 0019](0019-testing-and-ci.md)).
