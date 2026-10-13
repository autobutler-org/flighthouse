# 0033. Carry help links, needs-review, and metric titles through the schema

- Status: Proposed
- Date: 2026-10-13
- Amends: [ADR 0006](0006-core-schema.md), [ADR 0012](0012-renderers.md)

## Context

Issue #135 is the schema half of #129 and #131. `report.html` cannot show three things because the model does not
carry them. Everything below was read from the code and fixtures on `main` at `5b56086`.

- **Help links are dropped.** Every axe rule result has a `helpUrl`
  (`test/fixtures/axe/4.11.1/quark-48a76ae/photos.json` has
  `https://dequeuniversity.com/rules/axe/4.11/area-alt?application=axeAPI`). `_decodeRule` in
  `lib/src/adapters/axe/axe_adapter.dart` reads `id`, `impact`, `help`, and `nodes`, and nothing else. Lighthouse
  has no URL field on an audit. Its link is a Markdown link inside the audit's `description`
  (`test/fixtures/lighthouse/13.5.0/a11y-failures.json`: `largest-contentful-paint` ends with
  `[Learn more about the Largest Contentful Paint metric](https://developer.chrome.com/docs/lighthouse/...)`), and
  the adapter does not read `description`. attest 1.5.0 findings carry `criterion.understanding`, a WCAG
  Understanding page (`test/fixtures/attest/1.5.0/Settings.json`), which the adapter does not read either. The
  timeline source has no links.
- **Needs review lives only in the message.** axe `incomplete` results become findings at the same severity as
  violations. The only difference is a `Needs review: ` prefix on `Finding.message` (`_message` in the axe
  adapter). `report.html` explains that prefix in a note instead of badging it, and a `report.json` consumer would
  have to parse prose to tell the two apart.
- **Incomplete results do not affect scores today.** `_observe` in the axe adapter emits rule outcomes only for
  violations, passes, and inapplicable rules, and scoring reads only rule outcomes and measurements
  ([ADR 0008](0008-scoring.md), [ADR 0022](0022-measurement-weights.md)). That has to stay true.
- **They do affect the gate today.** A new needs-review finding at or above `minSeverity` fails `flighthouse ci`
  like a violation does (`lib/src/pipeline/gate.dart`). This ADR does not change that; see Open questions.
- **Metric titles are lost.** The Lighthouse adapter decodes each audit's `title` and uses it only as the message of
  a finding. A `Metric` is `name`, `value`, `unit`, so the Measurements table falls back to `metricTitle`, which
  turns `lcp-discovery-insight` into `Lcp discovery insight` (`lib/src/render/html_renderer.dart`).
- **The fingerprint is already at `v2`** (`lib/src/pipeline/fingerprint.dart`), an input of source, rule,
  normalized route, and normalized target ([ADR 0007](0007-fingerprints-and-normalization.md),
  [ADR 0024](0024-axe-target-identity.md)). `diffAgainstBaseline` refuses a baseline whose `fingerprintVersion`
  differs, so any change to the inputs forces `baseline --update` on every project, quark included.
- **The baseline file does not carry messages.** `BaselineFinding` is the fingerprint inputs plus severity and
  category (`lib/src/model/baseline.dart`), and it has its own `schemaVersion`.
- **The report reader is strict.** `reportFromJson` accepts only `schemaVersion` 1 and rejects unknown keys through
  `readObject`. Nothing under `lib/` reads `report.json` back today. Only `test/model/report_json_test.dart` does,
  but it is a published format and the acceptance criteria say an older report must still load.
- **ADR 0006 lists `Finding` and `Metric` field by field**, so this has to be a new ADR, not an edit.

## Options

All three options keep scoring as it is, keep the fingerprint at `v2`, and leave the baseline file unchanged. They
differ in where the data lives and in how `schemaVersion` handles it.

### Option A: optional keys, `schemaVersion` stays 1

`Finding` gains `helpUrl` and `needsReview`, and `Metric` gains `title`. The reader treats all three as optional
(`readOptionalField`): absent means `null`, `false`, and `null`. The writer omits a key when it holds the default,
so a report with no axe and no Lighthouse input is byte-identical to today's.

- Schema version: none. Fingerprint: none. Baseline: none.
- Adapters: axe, Lighthouse, and attest each fill the new fields. Renderer: link, badge, title.
- Upside: the smallest diff; old reports load with no version branch.
- Downside: one version number now names two shapes. An older flighthouse that reads a new report fails with
  "unknown key `helpUrl`" instead of the clear version message ADR 0006 promises. Omitting keys conditionally also
  breaks ADR 0006's fixed key order, which every other record in the file follows. `needsReview` as a `bool` gives
  no room for a third kind, for example Lighthouse `manual` audits, which are dropped today.

### Option B: explicit fields, `schemaVersion` 2 (recommended)

`Finding` gains `kind` (`violation` or `needs-review`) and `helpUrl`, and `Metric` gains `title`. Every key is
always written, `null` where there is no value, in a fixed order. The writer writes `schemaVersion` 2. The reader
accepts 1 and 2, and decodes a version 1 report with `kind: violation`, `helpUrl: null`, and `title: null`.

- Schema version: bumped to 2. Older flighthouse versions refuse a version 2 report with the existing version
  message. This flighthouse still reads version 1.
- Fingerprint: unchanged at `v2`. None of the new fields is an input.
- Baseline: unchanged. Its `schemaVersion` stays 1 and `BaselineFinding` gains nothing.
- Adapters: as in A, plus `kind`. The axe message loses its `Needs review: ` prefix, because `kind` now says it.
- Renderer: as in A, and the note explaining the prefix goes away.
- Upside: the data says what it means, every record keeps a fixed shape, and a version mismatch is reported as one.
  An enum can grow a case later, and the sealed `switch` rules make every consumer handle it.
- Downside: a version branch in `reportFromJson`, and the end-to-end and render goldens all change. Every axe and
  Lighthouse finding repeats its rule's help link once per target.

### Option C: a rule catalog, `schemaVersion` 2

`Report` gains `rules`: one entry per `(source, rule)` holding `title` and `helpUrl`. Findings, rule outcomes, and
measurements look their rule up there. For Lighthouse, a measurement's metric name is its audit id, so its title
comes from the same table. `Finding` still gains `kind`, since needs-review belongs to one result, not to the
rule.

- Schema version: bumped to 2, as in B. Fingerprint and baseline: unchanged.
- Adapters: each also emits catalog entries, and the pipeline has to merge them across artifacts. Two artifacts that
  disagree on a rule's title (two Lighthouse versions in one run) need a merge rule.
- Renderer: every lookup is a join, and a finding whose rule has no entry needs a fallback.
- Upside: no repetition. A rule with fifty failing nodes stores its link once, and passing rule outcomes get titles
  too.
- Downside: a new top-level type, a reference that can dangle, a merge rule that does not exist today, and the most
  code for the same three visible changes. The issue asks for none of the extra reach.

## Decision

Option B is recommended. If it is accepted:

- **`Finding`** gains, after `message`:
  - `kind`: a new enum `FindingKind`, serialized as `violation` or `needs-review`. Adapters emit `violation`
    except for axe `incomplete` results, which are `needs-review`.
  - `helpUrl`: `String?`. When present it is an absolute `http` or `https` URL. The reader rejects anything else
    with a `SchemaFailure` at its path, so the HTML renderer never emits a `javascript:` or relative link.
- **`Metric`** gains `title`: `String?`, after `unit`. It is a display label only. `name` stays the identity used by
  control points, sorting, and config.
- **`schemaVersion` becomes 2.** `currentSchemaVersion` is 2 and the writer always writes it. `reportFromJson`
  dispatches on the version. Version 1 uses today's key lists and fills in `kind: violation`, `helpUrl: null`, and
  `title: null`. Version 1 is decoded as written. A `Needs review: ` prefix in an old message is not parsed back
  into `kind`. Any other version is refused, naming the versions this build reads.
- **The fingerprint stays at `v2`.** `kind`, `helpUrl`, and `title` are not fingerprint inputs. A node that goes
  from incomplete to violation keeps its fingerprint, so a baselined finding stays accepted.
- **The baseline file is unchanged**, at baseline `schemaVersion` 1, with no new fields.
- **Scoring is unchanged.** `kind` is not read by `scoring.dart`. The category scores in the end-to-end golden must
  not move. That is the test.
- **Gate behavior is unchanged.** A `needs-review` finding counts as new exactly as it does today.
- **Dedupe:** when two findings share a fingerprint, `violation` wins over `needs-review`, and severity is merged as
  today. `helpUrl` and `metric` come from the first finding seen, as the rest of the finding does now.
- **Canonical order:** `kind` joins the finding sort key after severity, so output stays byte-stable.
- **Adapters.** Each one follows [ADR 0013](0013-adapter-contract.md): it reads the field from real output and
  documents it. Fixtures are re-recorded only if a field is missing from the current ones.
  - axe: `helpUrl` from the rule's `helpUrl`. When it is absent, the value is `null`. When it is present but not
    an `http` or `https` URL, the result is an `AdapterFailure` naming the JSON path. `kind` from the bucket. The
    message drops the `Needs review: ` prefix.
  - Lighthouse: `title` on every `Metric` the adapter builds, from the audit's `title`. `helpUrl` is the first
    Markdown link target in the audit's `description` that is an `http` or `https` URL, otherwise `null`. A
    `description` with no link is not a failure, because Lighthouse does not promise one.
  - attest: `helpUrl` from `criterion.understanding` when the finding has a `criterion`, otherwise `null`. Before
    this is built, attest's documentation has to confirm the field. If it is undocumented, the maintainer is asked
    first.
  - timeline: `helpUrl: null`, `title: null`.
- **Renderer** (amends ADR 0012):
  - Each finding with a `helpUrl` gets a "Learn more" link, `rel="noopener noreferrer"`, text escaped as now. A link
    is not a request, so the report stays self-contained.
  - `needs-review` findings get a distinct "Needs review" badge next to the severity, inside the same severity
    groups. The prose note about the message prefix is removed.
  - The Measurements table shows `metric.title` when present and falls back to `metricTitle(name)`.
- **Status lines on acceptance:** ADR 0006 gets "`Finding.kind`, `Finding.helpUrl`, `Metric.title`, and schema
  version 2 added by 0033". ADR 0012 gets "finding links and needs-review badge added by 0033". Neither Decision
  section is touched.
- **Order of work:** the schema change is the bottom of the stack (model, `report_json.dart`, normalize, dedupe, and
  the version 1 reader with its tests). The adapters come next with their fixture tests. The renderer and the
  goldens come last.

## Consequences

- `report.json` says what each finding is and where to read about it, without parsing prose.
- A report written by this version is refused by older flighthouse builds, with a version message. Since nothing in
  the CLI reads a report back, this affects only external consumers and older binaries.
- Every golden changes once: new keys, `schemaVersion` 2, and axe messages without the prefix. Scores must not.
- Baselines and fingerprints need no migration. No project has to run `baseline --update`.
- The Lighthouse link depends on the wording of `description`. A Lighthouse release that drops the Markdown link
  yields `null`, not a failure. The fixture test pins the current behavior.
- Help links repeat per target in `report.json`. At quark's size, this is a few kilobytes.

## Alternatives considered

- **Option A** (optional keys under version 1). Rejected in favor of B: it hides a shape change behind an unchanged
  version and gives up the fixed key order.
- **Option C** (a rule catalog). Rejected in favor of B: it adds a type, a reference, and a merge rule to save
  repetition nobody has asked to save. It can still be adopted later as a version 3 if `report.json` size becomes
  a problem.
- **Put `kind` in the fingerprint (scheme `v3`).** Rejected. A node moving from incomplete to violation would show
  up as a new finding plus a fixed one, and every baseline would need `baseline --update` for a display change.
- **`title` on `Measurement` instead of `Metric`.** Workable, and it would leave `Metric` a pure value. Not
  recommended because the title labels the metric's `name`, so it travels with it. That also lets a perf finding's
  `metric` show the same label as its measurement.
- **Exclude needs-review findings from the gate in the same change.** Kept out of scope: it is a CI behavior change
  under [ADR 0009](0009-baseline-and-ci-gate.md), not a schema change.

## Open questions

- Should `needs-review` findings be gated at all, or only reported? If not, that is a separate ADR amending ADR 0009
  and ADR 0027, now that `kind` makes the rule expressible.
- Should Lighthouse `manual` audits, dropped today, become findings with a new kind? `FindingKind` leaves room for
  it, but nothing here adds it.
- Does attest document `criterion.understanding` as stable output? To be checked against attest's docs before its
  adapter changes.
- The commit link from #135 needs a repository URL in `ReportMetadata`. It is optional in the issue and left out
  here. It would be another `schemaVersion` 2 field if wanted before this ships.
