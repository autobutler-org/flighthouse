---
name: resolve-issue
description: Take a GitHub issue from diagnosis to an open pull request: root cause, fix, local checks, commit, PR. Use when asked to "fix #N", "implement #N", "resolve #N", or "do issue N". Not for filing a new issue.
---

# Resolve an issue

Work one issue, `$ARGUMENTS`, end to end. Every rule in `AGENTS.md` applies; this is the order to apply them in.

1. **Read it.** `gh issue view <N> --comments`, and its parent epic. Restate the acceptance criteria in a sentence
   or two. Check `gh pr list --search "<N>"` so you are not duplicating an open PR. Then
   `gh issue edit <N> --add-assignee @me`.
2. **Check the ADRs it depends on.** Every ADR the issue or its epic cites must be `Accepted`. If one is still
   `Proposed`, stop and ask.
3. **Branch.** `fix/<N>-short-description` or `feat/<N>-short-description` off an up-to-date `main`.
4. **For an adapter, read the source first.** Open the tool's docs and a real sample output, record the fixture
   under `test/fixtures/<tool>/<tool-version>/` with a `SOURCE.md`, and only then write the parser. If the format
   is undocumented, stop and ask.
5. **Diagnose before editing.** For a bug, state the causal chain and write the failing test first.
6. **Find the siblings.** Grep for every other adapter, category, or renderer with the same defect, and fix them in
   the shared place.
7. **Decide: stack or one PR.** Default to a stack. Split whenever the work has parts a reviewer could merge on
   their own, and use the `gh-stack` skill for the mechanics: lay the layers out before writing files, foundation
   at the bottom.
   - A schema or `Result` change, then the code that consumes it.
   - An ADR, then the code that follows it.
   - A refactor, then the feature built on it.
   - A Makefile or tooling fix found on the way ships first, as its own PR at the bottom.
   - Every layer's body carries `Closes #<N>` plus a line naming the one under it: `Stacked on #<M>.`
8. **Implement the minimal change.** No new abstractions or dependencies without asking first.
9. **Verify locally.** `make check`, `make test`, and `make test/cli` when the CLI or a renderer changed. Run
   `make check/pana` when `pubspec.yaml`, `README.md`, `CHANGELOG.md`, or `example/` changed.
10. **Commit.** One focused, signed-off commit (`git commit -s`), conventional-commit subject, American spelling,
    no Claude Code session link.
11. **Open the PR.** Push, then `gh pr create` with a conventional-commit title, `Closes #<N>` in the body, and the
    PR template filled in.
12. **Report.** List exactly what you ran and what it showed. Never claim a check you did not perform.
