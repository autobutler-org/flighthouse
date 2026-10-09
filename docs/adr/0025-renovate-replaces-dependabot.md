# 0025. Renovate replaces Dependabot

- Status: Accepted
- Date: 2026-10-08

## Context

[ADR 0017](0017-dependency-policy.md) says Dependabot opens `pub` update PRs weekly, and `.github/dependabot.yml`
did that for `pub` and GitHub Actions. The rest of autobutler-org uses Renovate with one shared policy in
[autobutler-org/renovate-config](https://github.com/autobutler-org/renovate-config), and the Renovate app is
installed on every repository in the organization (read on 2026-10-08). quark's `renovate.json` extends that preset.
Running a different tool here means a second policy to maintain.

## Decision

- `renovate.json` at the repository root extends `github>autobutler-org/renovate-config` and adds nothing else.
- `.github/dependabot.yml` is removed, so the two tools never open duplicate PRs.
- A rule that applies only to flighthouse goes in this repository's `renovate.json`. A rule that applies to the
  organization goes in the shared preset.
- This amends the update-tooling sentence of ADR 0017. Every other rule in ADR 0017 stands: each dependency is
  listed there with its justification, and constraints are caret ranges on the latest release.

## Consequences

- Update PRs follow the org policy: daily instead of weekly, one grouped PR for `pub` and one for GitHub Actions,
  and a separate PR for each major update.
- Renovate opens a Dependency Dashboard issue in this repository.
- Renovate's commit prefixes, `chore(deps/dart):` and `chore(deps/github-actions):`, are conventional commits, so
  its PR titles pass the convention in `AGENTS.md`.
- A change to the shared preset changes behavior here without a commit in this repository.
