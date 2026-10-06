# 0001. Record architecture decisions

- Status: Accepted
- Date: 2026-10-06

## Context

flighthouse will be built mostly by coding agents working one issue at a time. A decision that lives only in a chat
transcript is lost to the next agent, and it gets re-decided differently.

## Decision

Every design decision that someone could reasonably have made differently is recorded here as a numbered Markdown
file, `NNNN-short-title.md`, with these sections:

- **Status**: `Proposed`, `Accepted`, `Rejected`, or `Superseded by NNNN`.
- **Date**: the day the status last changed.
- **Context**: the forces at play, with facts and where they were verified.
- **Decision**: what we will do, stated as rules an agent can follow.
- **Consequences**: what gets easier, what gets harder, what we now owe.
- **Alternatives considered** and **Open questions**, when there are any.

`Proposed` means not approved. Nothing is built on a Proposed ADR. The maintainer accepts an ADR by changing its
status, in a PR of its own or the PR that implements it.

An Accepted ADR's Decision section is never rewritten. A change of mind is a new ADR that supersedes it.

## Consequences

Every epic and ticket cites the ADRs it depends on, and the `resolve-issue` skill refuses to start on a Proposed
one.
