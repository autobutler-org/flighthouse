# Changelog

## 0.1.0

First release. Reads Lighthouse reports; other sources are in progress.

- `flighthouse collect`, `report`, `ci`, and `baseline [--update]`, with exit codes 0 passed, 1 gate failed,
  2 usage or config error, 3 unusable input.
- One unified, validated report schema (`report.json`), and a self-contained, accessible `report.html` with
  Lighthouse-style score gauges, light and dark themes, and a baseline comparison.
- Lighthouse 13 adapter. Scoring its output reproduces Lighthouse's own category scores.
- Lighthouse's log-normal metric scoring, ported exactly; weighted category and overall scores with configurable
  weights.
- Stable fingerprints and route normalization with go_router-style patterns, so the CI gate fails only on new
  findings or on score drops past configurable thresholds.
- Configuration in `flighthouse.yaml`, with errors that name the key, line, and column.
