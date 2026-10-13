#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("root")
parser.add_argument("manifest")
parser.add_argument("work")
parser.add_argument("--record", type=int, metavar="RUNS")
parser.add_argument("--machine")
args = parser.parse_args()

root = Path(args.root).resolve()
manifest_path = Path(args.manifest).resolve()
manifest = json.loads(manifest_path.read_text())
work = Path(args.work).resolve()
fixture = root / "integration" / "web_fixture"
report = work / "report"
routes = [entry["route"] for entry in manifest["routes"]]
control = next(entry["route"] for entry in manifest["routes"] if entry["control"])


def fail(message):
    raise SystemExit(message)


def write_config():
    path = work / "performance.yaml"
    config = {
        "app": "web-fixture-performance",
        "reportDir": str(report),
        "baseline": str(work / "flighthouse-baseline.json"),
        "web": {
            "projectDir": str(fixture),
            "build": {"command": ["true"], "outputDir": "build/web"},
            "serve": {"port": 0},
            "routes": routes,
            "readiness": {"timeoutSeconds": 90, "selector": '[role="main"]'},
            "viewport": {"width": 1280, "height": 800, "deviceScaleFactor": 1},
            "lighthouse": {"command": ["lighthouse"]},
            "axe": {"version": "4.11.1"},
        },
    }
    path.write_text(json.dumps(config, indent=2) + "\n")
    return str(path)


def run(config, command):
    completed = subprocess.run(
        ["dart", "run", "bin/flighthouse.dart", "--config", config, command],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        sys.stderr.write(completed.stdout + completed.stderr)
        fail(f"{command} exited {completed.returncode}")


def route_scores(config):
    run(config, "collect")
    run(config, "report")
    data = json.loads((report / "report.json").read_text())
    scores = {}
    for route in routes:
        items = [
            (outcome["weight"], 1.0 if outcome["passed"] else 0.0)
            for outcome in data["ruleOutcomes"]
            if outcome["category"] == "perf" and outcome["route"] == route
        ] + [
            (measurement["weight"], measurement["toolScore"])
            for measurement in data["measurements"]
            if measurement["category"] == "perf"
            and measurement["route"] == route
            and measurement["weight"] > 0
            and measurement["toolScore"] is not None
        ]
        total = sum(weight for weight, _ in items)
        if total == 0:
            fail(f"{route} has no weighted performance score in report.json")
        scores[route] = round(sum(weight * score for weight, score in items) / total, 4)
    return scores


def check_separation(scores, tolerance):
    for route in routes:
        if route != control and scores[route] > scores[control] - tolerance:
            fail(
                f"{route} scored {scores[route]}, not at least {tolerance} below "
                f"{control} at {scores[control]}"
            )


def record(config, runs):
    if runs < 2:
        fail("record at least two runs, a range from one run is not a range")
    tolerance = manifest["tolerance"]
    samples = {route: [] for route in routes}
    for index in range(runs):
        scores = route_scores(config)
        check_separation(scores, tolerance)
        for route in routes:
            samples[route].append(scores[route])
        print(f"run {index + 1}/{runs}: {scores}")
    manifest["recorded"] = {
        "date": date.today().isoformat(),
        "runs": runs,
        "machine": args.machine or manifest["recorded"]["machine"],
        "lighthouse": json.loads((report / "report.json").read_text())["metadata"][
            "toolVersions"
        ]["lighthouse"],
    }
    for entry in manifest["routes"]:
        entry["scores"] = samples[entry["route"]]
        entry["min"] = min(samples[entry["route"]])
        entry["max"] = max(samples[entry["route"]])
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"recorded {runs} runs to {manifest_path}")


def check(config):
    tolerance = manifest["tolerance"]
    scores = route_scores(config)
    recorded = manifest["recorded"]
    print(
        f"performance ranges from {recorded['runs']} runs on {recorded['date']}, "
        f"tolerance {tolerance}"
    )
    outside = []
    for entry in manifest["routes"]:
        low = round(entry["min"] - tolerance, 4)
        high = round(entry["max"] + tolerance, 4)
        score = scores[entry["route"]]
        within = low <= score <= high
        status = "within" if within else "outside"
        print(f"  {entry['route']}: {score} {status} [{low}, {high}] ({entry['cost']})")
        if not within:
            outside.append(entry["route"])
    if outside:
        fail(f"performance scores outside their recorded range: {', '.join(outside)}")
    check_separation(scores, tolerance)
    print(f"every slowed route scores at least {tolerance} below {control}")


work.mkdir(parents=True, exist_ok=True)
config = write_config()
if args.record:
    record(config, args.record)
else:
    check(config)
