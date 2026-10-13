#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
manifest = json.loads(Path(sys.argv[2]).read_text())["planted"]
work = Path(sys.argv[3]).resolve()
fixture = root / "integration" / "web_fixture"
report = work / "report"
baseline = work / "flighthouse-baseline.json"
NEEDS_REVIEW = "Needs review:"


def fail(message):
    raise SystemExit(message)


def config_for(defects):
    path = work / f"defects-{'-'.join(defects) or 'none'}.yaml"
    config = {
        "app": "web-fixture-toggles",
        "reportDir": str(report),
        "baseline": str(baseline),
        "gate": {"maxScoreDrop": {"overall": 100, "perf": 100}},
        "web": {
            "projectDir": str(fixture),
            "build": {"command": ["true"], "outputDir": "build/web"},
            "serve": {"port": 0},
            "routes": [f"/planted?defects={','.join(defects)}"],
            "readiness": {"timeoutSeconds": 90, "selector": '[role="main"]'},
            "viewport": {"width": 1280, "height": 800, "deviceScaleFactor": 1},
            "lighthouse": {"command": ["lighthouse"]},
            "axe": {"version": "4.11.1"},
        },
    }
    path.write_text(json.dumps(config, indent=2) + "\n")
    return str(path)


def run(config, args):
    return subprocess.run(
        ["dart", "run", "bin/flighthouse.dart", "--config", config, *args],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )


def checked(config, args, expected):
    completed = run(config, args)
    if completed.returncode != expected:
        sys.stderr.write(completed.stdout + completed.stderr)
        fail(f"{' '.join(args)} exited {completed.returncode}, expected {expected}")
    return completed


def fingerprints(path):
    return {
        finding["fingerprint"]: finding
        for finding in json.loads(path.read_text())["findings"]
    }


def collect_and_ci(defects, expected):
    config = config_for(defects)
    checked(config, ["collect"], 0)
    return config, checked(config, ["ci"], expected)


work.mkdir(parents=True, exist_ok=True)
entry = next(entry for entry in manifest if entry["detectable"])

clean = config_for([])
checked(clean, ["collect"], 0)
checked(clean, ["baseline", "--update"], 0)
_, passed = collect_and_ci([], 0)
if "gate passed" not in passed.stdout:
    fail("clean ci did not report gate passed")
print("clean build passes against its own baseline")

_, failed = collect_and_ci([entry["toggle"]], 1)
known = fingerprints(baseline)
new = [
    finding
    for fingerprint, finding in fingerprints(report / "report.json").items()
    if fingerprint not in known and not finding["message"].startswith(NEEDS_REVIEW)
]
expected = {(source, entry["rule"], entry["route"]) for source in entry["sources"]}
actual = {(finding["source"], finding["rule"], finding["route"]) for finding in new}
if actual != expected:
    sys.stderr.write(failed.stdout + failed.stderr)
    fail(f"turning on {entry['toggle']} added {sorted(actual)}, expected {sorted(expected)}")
print(f"turning on {entry['toggle']} fails ci with only {entry['rule']} from {', '.join(entry['sources'])}")

_, fixed = collect_and_ci([], 0)
if "gate passed" not in fixed.stdout:
    fail("fixed ci did not report gate passed")
print(f"turning off {entry['toggle']} passes ci again")
