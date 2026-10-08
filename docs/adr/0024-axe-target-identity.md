# 0024. Preserve distinct axe targets without generated Flutter IDs

- Status: Accepted; supersedes ADR 0007's axe target-normalization rule
- Date: 2026-10-08

## Context

Accepted [ADR 0007](0007-fingerprints-and-normalization.md) suggests removing generated IDs and `nth-child`
indices, with the exact axe rules deferred to phase 2. The [quark measurement](../phases/semantics-signal.md)
shows that this loses findings: two `nested-interactive` nodes become the same target after removing ordinals,
six login `region` nodes become two, and four files `region` nodes become two.

The two measured builds initially had identical targets, but later navigation changed `/files` IDs. Axe's
`absolutePaths` option retained generated IDs. Its documented `ancestry` option returned ID-free paths that
matched between both builds and startup versus later activation while distinguishing those nodes.

Raw axe targets also encode iframe and shadow boundaries as nested arrays. Flattening them without boundaries
can create additional collisions. Accessible names are not a dedicated guaranteed field in axe's result, and
HTML snippets can be truncated, so names cannot be reconstructed reliably from a snippet alone.

## Decision

- The phase-2 axe runner requests `ancestry: true` and preserves the complete unmodified result. The adapter
  uses ancestry for `normalizedTarget` when present and keeps the original selector and HTML for display.
- Preserve the ordered iframe/shadow structure using canonical JSON encoding of the nested selector array.
  Do not join arbitrary strings with a separator that can appear in a selector.
- For a path containing a Flutter view, anchor identity at `flutter-view`, dropping preceding document-shell
  ancestors and that view's sibling ordinal. Preserve every descendant ordinal, including the semantics host's
  ordinal. Those positions distinguish repeated nodes; a document-shell script insertion should not rename them.
- Do not strip normal application IDs. Ancestry contains no generated IDs in the measured version. If an imported
  result lacks ancestry and its target contains a generated `flt-semantic-node-N` ID, return an actionable
  `AdapterFailure` asking for output captured with `ancestry: true`, rather than create an ambiguous fingerprint.
  Non-Flutter imported targets without ancestry may retain their exact selectors as the fallback.
- All transformations are pure, idempotent, and validated against recorded real output. Empty or malformed target
  structures fail with a JSON path. Preserve both entries of a repeated-rule collision fixture.
- Keep source, rule, route normalization, field escaping, and hashing from ADR 0007. Bump the global fingerprint
  version from `v1` to `v2` when this adapter ships, consistent with ADR 0007's migration rule. Existing baselines
  must be updated explicitly; `ci` explains the mismatch and never silently accepts a baseline migration.
- ADR 0007 remains Accepted for every other fingerprint and normalization rule. Its status records this narrow
  supersession without rewriting its original decision in place.

## Consequences

Equivalent measured controls retain their identity despite runtime-generated IDs, and distinct controls remain
distinct. Structural UI changes and responsive layout changes can still alter ancestry. Keep the configured
viewport and capture conditions consistent; the evidence does not promise stability across arbitrary layouts,
locales, data ordering, or multiple Flutter views.

Imported Flutter axe results need ancestry. This explicit compatibility limit is preferable to silently suppressing
new serious findings through deduplication. The fingerprint version change is visible and reviewable, including
its effects on the existing attest and Lighthouse baselines.

## Alternatives considered

- Strip IDs and ordinals: observed collisions hide independent findings.
- Keep generated IDs: observed churn creates false new findings in unchanged pages.
- Use `absolutePaths: true`: observed output still contains generated IDs.
- Infer role and accessible name from HTML: snippets lack guaranteed complete names, and repeated unnamed controls
  still need disambiguation.
- Hash the raw HTML: inline layout and generated IDs change without a meaningful control change.

## Open questions

- Multi-view identity needs additional real fixtures before supporting more than the measured single Flutter view.
- #25 must demonstrate unchanged fingerprints across the paired fixtures, non-collision for repeated siblings,
  frame/shadow boundary preservation, fallback errors, and fingerprint-version gate behavior.
