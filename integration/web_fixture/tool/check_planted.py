#!/usr/bin/env python3
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())["planted"]
findings = json.loads(Path(sys.argv[2]).read_text())["findings"]
NEEDS_REVIEW = "Needs review:"


def reported(entry, source):
    return any(
        finding["source"] == source
        and finding["rule"] == entry["rule"]
        and finding["route"] == entry["route"]
        and finding["category"] == entry["category"]
        and not finding["message"].startswith(NEEDS_REVIEW)
        for finding in findings
    )


detected = []
missing = []
surprises = []
for entry in manifest:
    found = bool(entry["sources"]) and all(
        reported(entry, source) for source in entry["sources"]
    )
    if found:
        detected.append(entry)
    if entry["detectable"] and not found:
        missing.append(entry)
    if not entry["detectable"] and any(
        reported(entry, source) for source in entry["sources"]
    ):
        surprises.append(entry)

print(f"planted defects detected: {len(detected)}/{len(manifest)}")
for entry in manifest:
    status = "detected" if entry in detected else "not detected"
    sources = ", ".join(entry["sources"]) or "no tool"
    rule = entry["rule"] or "no rule"
    line = f"  {status}: {entry['defect']} ({rule} from {sources})"
    if not entry["detectable"]:
        line += f", expected: {entry['reason']}"
    print(line)
if missing:
    names = ", ".join(entry["defect"] for entry in missing)
    raise SystemExit(f"planted defects not detected: {names}")
if surprises:
    names = ", ".join(entry["defect"] for entry in surprises)
    raise SystemExit(f"defects marked undetectable were detected, update planted.json: {names}")
