# 0012. JSON and HTML renderers

- Status: Accepted
- Date: 2026-10-06

## Decision

- Renderers are pure: `String renderJson(Report)` and `String renderHtml(Report, BaselineDiff?)`.
- `report.json` is the canonical serialization from [ADR 0006](0006-core-schema.md), pretty-printed with two-space
  indentation.
- `report.html` is one self-contained file: inline CSS, inline SVG score gauges, no external fonts, scripts, or
  requests, so it can be uploaded as a CI artifact and opened offline. Expand and collapse use `<details>`; there is
  no JavaScript unless a later need justifies it.
- Light and dark themes follow `prefers-color-scheme`.
- Layout follows Lighthouse: an overall gauge, a gauge per category ("not measured" when null), then findings grouped
  by category and severity, with new findings flagged when a baseline diff is present.
- All interpolated text goes through one tested HTML-escaping function. No template engine dependency.
- Golden tests compare both renderers against committed outputs for the end-to-end fixture.
