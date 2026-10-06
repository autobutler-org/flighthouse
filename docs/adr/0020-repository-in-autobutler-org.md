# 0020. The repository lives in autobutler-org

- Status: Accepted
- Date: 2026-10-06

## Context

flighthouse started as `github.com/brandonapol/flighthouse`. The maintainer wants it to be part of the autobutler-org
organization, alongside quark, its first real target. An empty `autobutler-org/flighthouse` had already been
created, which rules out a GitHub repository transfer.

## Decision

- The canonical repository is `github.com/autobutler-org/flighthouse`. The pubspec `repository` and `issue_tracker`,
  the security advisory link, and the sub-issue commands in `AGENTS.md` point there.
- The git history was pushed into the org repository. The `main` ruleset and merge settings were copied from the
  personal repository.
- Epics and tasks were filed again in the original order, so issue numbers #1 to #35 mean the same thing in both
  repositories. PR #36 of the personal repository, which added CI, exists only there; its commit is in the history.
- `brandonapol/flighthouse` is retired. It should be archived with a pointer to the org repository.

## Consequences

- The repository URLs in ADRs 0003 and 0018 were amended in place to the new location. Nothing else in those
  decisions changed.
