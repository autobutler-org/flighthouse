# attest_flutter 1.5.0 fixtures

Real attest `AuditReport` JSON, recorded on 2026-10-07.

| File            | Screen                                                                            |
| --------------- | --------------------------------------------------------------------------------- |
| `SignIn.json`   | A plain Material sign-in form: a large "Sign in" text, a labeled `TextField`, and an `ElevatedButton` |
| `Settings.json` | A deliberately broken screen: an unlabeled `IconButton`, an `Image` with no semantics label, low-contrast text, and an unlabeled `TextField` |

## How they were produced

`a11y_fixture_test.dart.txt` is the exact widget test, renamed so `dart test` doesn't pick it up. It ran in a fresh
`flutter create --empty` project on Flutter 3.47.6 with `dev: attest_flutter: 1.5.0`, which resolved attest core
1.11.0:

```sh
flutter test test/a11y_test.dart
```

It writes each report the way attest_cli's README says to: `jsonEncode(report.toJson())` into `build/a11y/`.

The only edit: the scratch project's absolute path in `location.file` was replaced with `/work/app`, so no local
path is committed. Nothing else was changed.

## Format, checked against

`github.com/sahland/attest`, `main` as of 2026-07-17:

- `packages/attest/lib/src/model/audit_report.dart`, `finding.dart`, `audit_meta.dart`, `severity.dart`
- `packages/attest/lib/src/engine/rule_engine.dart` (`RuleEngine.standard()`, the 15 rules) and each rule's source
  for its id and severities
- `packages/attest/lib/src/engine/fingerprint.dart` (what attest's fingerprint hashes)
- `packages/attest_cli/README.md` ("Producing reports")

## Mapping

| attest                                | flighthouse                                                     |
| ------------------------------------- | --------------------------------------------------------------- |
| one report file                       | one screen; `meta.screenName` is the route                      |
| `meta.toolVersion` (attest_flutter's) | tool version; majors other than 1 are refused                   |
| finding `ruleId`                      | rule                                                            |
| finding `severity` `error`, `warning`, `info` | `serious`, `moderate`, `info`                           |
| finding `fingerprint`                 | target, so our fingerprint is as stable as attest's (rule, WCAG criterion, structural node path, normalized label; never coordinates) |
| finding `message` and `location`      | message, with `(file:line)` appended                            |
| each standard rule with no finding    | a passed `RuleOutcome`, weighted by the rule's worst severity (serious 7, moderate 3) |
| each rule with a finding              | a failed `RuleOutcome`, weighted by its worst finding           |

Every finding is accessibility (`a11y`). attest's `criterion`, `confidence`, `suggestion`, `bounds`, `gateSeverity`,
and `transcript` are not used yet.

## Known limitations

- **Rules disabled in `RuleConfig.disabledRules` count as passed.** The report doesn't record which rules ran.
- **attest emits negative hex fingerprints** (`-67d6298c587ef6b` in `SignIn.json`). Its 64-bit FNV-1a overflows
  Dart's signed integers, and `toUnsigned(64)` can't make that positive on the VM. It's harmless here, since any
  string is a valid target, but it looks like an upstream bug worth reporting to attest.
