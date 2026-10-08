# 0007. Fingerprints and normalization

- Status: Accepted; axe target normalization superseded by ADR 0024
- Date: 2026-10-06

## Context

The baseline gate is only as good as fingerprint stability. A fingerprint that changes when nothing meaningful
changed makes every run report "new" findings, and the gate gets switched off.

Known sources of churn:

- Routes with ids in them (quark has `/files/:path(.*)` and query parameters such as `?album=`).
- Tool messages, which get reworded across tool versions.
- Flutter web semantics DOM nodes are generated elements with ids assigned at runtime, so an axe target selector
  can include an id that differs between builds. This has to be confirmed in the phase 2 spike.

## Decision

- `fingerprint = sha256("v1" | source | rule | normalizedRoute | normalizedTarget)` as lowercase hex, with `|` as the
  separator and each field escaped so it cannot contain a raw `|`. Uses `package:crypto`.
- The message is not part of the fingerprint.
- Route normalization, a pure function of config:
  - strip the query string and fragment, drop a trailing slash, keep case;
  - match against the configured route patterns (`routes.patterns` in config, go_router syntax) and replace the
    matched route with its pattern, so `/files/a/b.txt` becomes `/files/:path(.*)`.
- Target normalization, per source: each adapter supplies a pure function that strips volatile parts. ADR 0024
  supersedes the axe-specific rule after real output showed that removing child ordinals merges distinct findings.
- `v1` is the fingerprint scheme version. Changing normalization bumps it, and `baseline --update` is the migration.

## Consequences

- Fingerprints are recomputable from a finding's own fields.
- A normalization bug is fixed in one function and a fingerprint version bump, not in each adapter.

## Open questions

- How stable are axe targets on Flutter web builds? Answered by the phase 2 spike, which compares two builds of the
  same commit.
