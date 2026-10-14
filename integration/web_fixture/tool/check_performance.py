#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path


def fail(message):
    raise SystemExit(message)


def control_route(manifest):
    return next(entry["route"] for entry in manifest["routes"] if entry["control"])


def config_for(fixture, report, work, routes):
    return {
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


def scores_from_report(data, routes):
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


def gate_failures(scores, control, margin, floor):
    below_floor = [
        f"{route} scored {score}, below the floor {floor}"
        for route, score in scores.items()
        if score < floor
    ]
    too_close = [
        f"{route} scored {score}, not at least {margin} below {control} at {scores[control]}"
        for route, score in scores.items()
        if route != control and score > round(scores[control] - margin, 4)
    ]
    return below_floor + too_close


def check_gate(scores, control, manifest):
    failures = gate_failures(scores, control, manifest["margin"], manifest["floor"])
    if failures:
        fail("\n".join(failures))


def range_notes(manifest, scores):
    notes = []
    for entry in manifest["routes"]:
        score = scores[entry["route"]]
        if score < entry["min"]:
            place = "below"
        elif score > entry["max"]:
            place = "above"
        else:
            place = "within"
        notes.append(
            f"{entry['route']}: {score} {place} recorded [{entry['min']}, {entry['max']}] "
            f"({entry['cost']})"
        )
    return notes


def recorded_manifest(manifest, samples, recorded):
    routes = [
        {
            **entry,
            "scores": samples[entry["route"]],
            "min": min(samples[entry["route"]]),
            "max": max(samples[entry["route"]]),
        }
        for entry in manifest["routes"]
    ]
    return {**manifest, "recorded": recorded, "routes": routes}


def run(root, config, command):
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


def route_scores(root, config, report, routes):
    run(root, config, "collect")
    run(root, config, "report")
    return scores_from_report(json.loads((report / "report.json").read_text()), routes)


def record(root, config, report, manifest, manifest_path, runs, machine):
    if runs < 2:
        fail("record at least two runs, a range from one run is not a range")
    routes = [entry["route"] for entry in manifest["routes"]]
    control = control_route(manifest)
    samples = {route: [] for route in routes}
    for index in range(runs):
        scores = route_scores(root, config, report, routes)
        check_gate(scores, control, manifest)
        for route in routes:
            samples[route].append(scores[route])
        print(f"run {index + 1}/{runs}: {scores}")
    recorded = {
        "date": date.today().isoformat(),
        "runs": runs,
        "machine": machine or manifest["recorded"]["machine"],
        "lighthouse": json.loads((report / "report.json").read_text())["metadata"][
            "toolVersions"
        ]["lighthouse"],
    }
    updated = recorded_manifest(manifest, samples, recorded)
    manifest_path.write_text(json.dumps(updated, indent=2) + "\n")
    print(f"recorded {runs} runs to {manifest_path}")


def check(root, config, report, manifest):
    routes = [entry["route"] for entry in manifest["routes"]]
    control = control_route(manifest)
    scores = route_scores(root, config, report, routes)
    recorded = manifest["recorded"]
    print(
        f"recorded ranges from {recorded['runs']} runs on {recorded['date']}, "
        "informational only"
    )
    for note in range_notes(manifest, scores):
        print(f"  {note}")
    check_gate(scores, control, manifest)
    print(
        f"every route scores at least {manifest['floor']}, and every slowed route "
        f"scores at least {manifest['margin']} below {control}"
    )


def main():
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

    work.mkdir(parents=True, exist_ok=True)
    config_path = work / "performance.yaml"
    config_path.write_text(
        json.dumps(config_for(fixture, report, work, routes), indent=2) + "\n"
    )
    config = str(config_path)
    if args.record:
        record(root, config, report, manifest, manifest_path, args.record, args.machine)
    else:
        check(root, config, report, manifest)


if __name__ == "__main__":
    main()
