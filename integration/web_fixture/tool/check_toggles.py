#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

NEEDS_REVIEW = "Needs review:"


def fail(message):
    raise SystemExit(message)


def defect_set(defects):
    return ",".join(defects) or "none"


def config_name(defects):
    return f"defects-{'-'.join(defects) or 'none'}.yaml"


def config_for(defects, fixture, report, baseline):
    return {
        "app": "web-fixture-toggles",
        "reportDir": str(report),
        "baseline": str(baseline),
        "gate": {"maxScoreDrop": {"overall": 100, "perf": 100}},
        "web": {
            "projectDir": str(fixture),
            "build": {"command": ["true"], "outputDir": "build/web"},
            "serve": {"port": 0},
            "routes": [f"/planted?defects={defect_set(defects)}"],
            "readiness": {"timeoutSeconds": 90, "selector": '[role="main"]'},
            "viewport": {"width": 1280, "height": 800, "deviceScaleFactor": 1},
            "lighthouse": {"command": ["lighthouse"]},
            "axe": {"version": "4.11.1"},
        },
    }


def toggled_entry(manifest):
    return next(entry for entry in manifest if entry["detectable"])


def by_fingerprint(findings):
    return {finding["fingerprint"]: finding for finding in findings}


def new_findings(current, known, category):
    seen = by_fingerprint(known)
    return [
        finding
        for fingerprint, finding in by_fingerprint(current).items()
        if fingerprint not in seen
        and finding["category"] == category
        and not finding["message"].startswith(NEEDS_REVIEW)
    ]


def expected_keys(entry):
    return {(source, entry["rule"], entry["route"]) for source in entry["sources"]}


def actual_keys(findings):
    return {(finding["source"], finding["rule"], finding["route"]) for finding in findings}


def main():
    root = Path(sys.argv[1]).resolve()
    manifest = json.loads(Path(sys.argv[2]).read_text())["planted"]
    work = Path(sys.argv[3]).resolve()
    fixture = root / "integration" / "web_fixture"
    report = work / "report"
    baseline = work / "flighthouse-baseline.json"

    def write_config(defects):
        path = work / config_name(defects)
        config = config_for(defects, fixture, report, baseline)
        path.write_text(json.dumps(config, indent=2) + "\n")
        return str(path)

    def checked(config, args, expected):
        completed = subprocess.run(
            ["dart", "run", "bin/flighthouse.dart", "--config", config, *args],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )
        if completed.returncode != expected:
            sys.stderr.write(completed.stdout + completed.stderr)
            fail(f"{' '.join(args)} exited {completed.returncode}, expected {expected}")
        return completed

    def collect_and_ci(defects, expected):
        config = write_config(defects)
        checked(config, ["collect"], 0)
        return checked(config, ["ci"], expected)

    def findings_in(path):
        return json.loads(path.read_text())["findings"]

    work.mkdir(parents=True, exist_ok=True)
    entry = toggled_entry(manifest)

    clean = write_config([])
    checked(clean, ["collect"], 0)
    checked(clean, ["baseline", "--update"], 0)
    passed = collect_and_ci([], 0)
    if "gate passed" not in passed.stdout:
        fail("clean ci did not report gate passed")
    print("clean build passes against its own baseline")

    failed = collect_and_ci([entry["toggle"]], 1)
    new = new_findings(findings_in(report / "report.json"), findings_in(baseline), entry["category"])
    expected = expected_keys(entry)
    actual = actual_keys(new)
    if actual != expected:
        sys.stderr.write(failed.stdout + failed.stderr)
        fail(f"turning on {entry['toggle']} added {sorted(actual)}, expected {sorted(expected)}")
    print(
        f"turning on {entry['toggle']} fails ci with only {entry['rule']} "
        f"from {', '.join(entry['sources'])}"
    )

    fixed = collect_and_ci([], 0)
    if "gate passed" not in fixed.stdout:
        fail("fixed ci did not report gate passed")
    print(f"turning off {entry['toggle']} passes ci again")


if __name__ == "__main__":
    main()
