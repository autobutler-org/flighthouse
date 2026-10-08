# Architecture decision records

Format and process: [ADR 0001](0001-record-architecture-decisions.md). `Proposed` means not yet approved by the
maintainer; nothing is built on it.

| ADR                                                   | Decision                                              | Status    |
| ----------------------------------------------------- | ----------------------------------------------------- | --------- |
| [0001](0001-record-architecture-decisions.md)         | Record architecture decisions                         | Accepted  |
| [0002](0002-aggregate-existing-tools.md)              | Aggregate existing tools, do not reimplement them     | Accepted  |
| [0003](0003-package-layout.md)                        | Flutter-free core, Flutter companion package          | Accepted  |
| [0004](0004-functional-core-imperative-shell.md)      | Functional core, imperative shell                     | Accepted  |
| [0005](0005-failure-as-values.md)                     | In-repo sealed Result, no FP library                  | Accepted  |
| [0006](0006-core-schema.md)                           | Core schema                                           | Accepted  |
| [0007](0007-fingerprints-and-normalization.md)        | Fingerprints and normalization                        | Accepted  |
| [0008](0008-scoring.md)                               | Scoring: Lighthouse log-normal port, weights          | Accepted  |
| [0009](0009-baseline-and-ci-gate.md)                  | Baseline diff and CI gate                             | Accepted  |
| [0010](0010-configuration.md)                         | `flighthouse.yaml` configuration                      | Accepted  |
| [0011](0011-cli.md)                                   | CLI commands and exit codes                           | Accepted  |
| [0012](0012-renderers.md)                             | JSON and self-contained HTML renderers                | Accepted  |
| [0013](0013-adapter-contract.md)                      | Adapter contract and the docs-first rule              | Accepted  |
| [0014](0014-external-tools.md)                        | External tools are optional subprocesses              | Accepted  |
| [0015](0015-browser-automation-and-axe.md)            | Browser automation and axe                            | Proposed, pending spike |
| [0016](0016-semantics-enabled-web-builds.md)          | Semantics-enabled Flutter web builds                  | Proposed, pending measurement |
| [0017](0017-dependency-policy.md)                     | Dependency policy                                     | Accepted  |
| [0018](0018-packaging-and-pub-dev.md)                 | Packaging for pub.dev                                 | Accepted  |
| [0019](0019-testing-and-ci.md)                        | Testing and CI                                        | Accepted  |
| [0020](0020-repository-in-autobutler-org.md)          | The repository lives in autobutler-org                | Accepted  |
| [0021](0021-configuration-refinements.md)             | Configuration refinements found while implementing    | Accepted, flagged for review |
| [0022](0022-measurement-weights.md)                   | Measurements carry a weight                           | Accepted  |
| [0023](0023-web-runner-configuration.md)              | Optional web build, routes, auth, and capture config   | Proposed, checkpoint |
| [0024](0024-axe-target-identity.md)                   | Preserve distinct axe targets without generated IDs   | Proposed, checkpoint |

ADRs marked Accepted record decisions the maintainer already made in the project brief.
