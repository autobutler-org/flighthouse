# 0019. Testing and CI

- Status: Accepted
- Date: 2026-10-06

## Decision

Tests:

- Unit tests for every pure function, under `test/` mirroring `lib/src/`.
- Fixture tests for each adapter, over real recorded outputs ([ADR 0013](0013-adapter-contract.md)), including one
  malformed-input case per required field.
- One end-to-end test that runs the whole pipeline on recorded fixtures and compares `report.json` and
  `report.html` with committed goldens.
- `test/architecture_test.dart` enforces the layering rules in `AGENTS.md`.

GitHub Actions, `.github/workflows/check.yml`, on `pull_request`, `merge_group`, and `workflow_dispatch`:

- Runs in the `dart:stable` container image, which has no Node, proving the core needs none.
- Steps: `make setup/deps`, `make check`, `make test`, `make test/cli`, `make check/pana`.
- `permissions: contents: read`, and concurrency that cancels superseded runs of the same PR, as in quark.

Phase 2 adds `.github/workflows/web.yml`, which installs Node, Lighthouse, and Chrome, builds a small Flutter web
fixture app, and runs `flighthouse collect` against it. It is the only workflow with Node.

`git/hooks/pre-commit` runs `make check` locally; `git/hooks/commit-msg` rejects AI attribution in commit messages.
