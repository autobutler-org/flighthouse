# Epics

One epic per phase. Phases 1 to 3 are filed as GitHub issues, with each task as a sub-issue of its epic
([AGENTS.md](../../AGENTS.md), Scope discipline). The GitHub issues are the live record; these files are the original
drafts. Phase 4 stays a draft until there is demand.

| Epic                                      | Phase | Depends on                     |
| ----------------------------------------- | ----- | ------------------------------ |
| [01 Core pipeline and CI gate](01-core-pipeline-and-ci-gate.md), #1 | 1 | ADRs 0003, 0005 to 0013, 0017 to 0019 |
| [02 Flutter web runner and axe](02-web-runner-and-axe.md), #16 | 2 | Epic 01, ADRs 0014 to 0016      |
| [03 Frame timing and flutter_lighthouse](03-frame-timing-and-flutter-lighthouse.md), #29 | 3 | Epic 01, ADR 0003 (companion package) |
| [04 DevTools extension](04-devtools-extension.md)               | 4 | Demand                          |

Work one phase at a time. Each epic ends with a written summary: what works, what was assumed, what could not be
verified.
