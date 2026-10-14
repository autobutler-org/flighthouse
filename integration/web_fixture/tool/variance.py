#!/usr/bin/env python3
import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from check_planted import detected_by_all

ROUTES = ["/public", "/planted"]


def fail(message):
    raise SystemExit(message)


def config_for(fixture, report, work):
    return {
        "app": "web-fixture-variance",
        "reportDir": str(report),
        "baseline": str(work / "flighthouse-baseline.json"),
        "web": {
            "projectDir": str(fixture),
            "build": {"command": ["true"], "outputDir": "build/web"},
            "serve": {"port": 0},
            "routes": ROUTES,
            "readiness": {"timeoutSeconds": 90, "selector": '[role="main"]'},
            "viewport": {"width": 1280, "height": 800, "deviceScaleFactor": 1},
            "lighthouse": {"command": ["lighthouse"]},
            "axe": {"version": "4.11.1"},
        },
    }


def run(root, config, command):
    return subprocess.run(
        ["dart", "run", "bin/flighthouse.dart", "--config", config, command],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )


def collect_once(root, config, work, planted, index):
    report = work / "report"
    shutil.rmtree(report, ignore_errors=True)
    for command in ["collect", "report"]:
        completed = run(root, config, command)
        if completed.returncode != 0:
            tail = (completed.stdout + completed.stderr).strip().splitlines()[-5:]
            return {"run": index, "failed": f"{command} exited {completed.returncode}", "output": tail}
    data = json.loads((report / "report.json").read_text())
    shutil.copy(report / "report.json", work / "runs" / f"run-{index:02d}.json")
    return {
        "run": index,
        "scores": {"overall": data["scores"]["overall"], **data["scores"]["categories"]},
        "detected": {entry["defect"]: detected_by_all(entry, data["findings"]) for entry in planted},
        "toolVersions": data["metadata"]["toolVersions"],
    }


def spread(values):
    present = [value for value in values if value is not None]
    if not present:
        return {"min": None, "median": None, "max": None}
    return {
        "min": round(min(present), 4),
        "median": round(statistics.median(present), 4),
        "max": round(max(present), 4),
    }


def summarize(planted, runs):
    completed = [entry for entry in runs if "failed" not in entry]
    failed_runs = len(runs) - len(completed)
    names = list(dict.fromkeys(name for entry in completed for name in entry["scores"]))
    scores = {}
    for name in names:
        values = [
            None if entry["scores"].get(name) is None else round(entry["scores"][name], 4)
            for entry in completed
        ]
        scores[name] = {
            **spread(values),
            "failures": failed_runs,
            "values": values,
        }
    detections = {}
    for entry in planted:
        hits = [run_entry["detected"][entry["defect"]] for run_entry in completed]
        expected = entry["detectable"]
        detections[entry["defect"]] = {
            **spread([1.0 if hit else 0.0 for hit in hits]),
            "expected": expected,
            "detected": sum(hits),
            "failures": failed_runs + sum(hit != expected for hit in hits),
        }
    return {"runs": len(runs), "failedRuns": failed_runs, "scores": scores, "detections": detections}


def show(value):
    return "null" if value is None else f"{value:.4f}"


def print_table(title, rows):
    print(f"  {title:<40} {'min':>7} {'median':>7} {'max':>7} {'failures':>8}")
    for name, row in rows.items():
        print(
            f"  {name:<40} {show(row['min']):>7} {show(row['median']):>7} "
            f"{show(row['max']):>7} {row['failures']:>8}"
        )


def print_summary(summary):
    print(f"{summary['runs']} runs, {summary['failedRuns']} failed")
    print_table("score, null when not measured", summary["scores"])
    print_table("planted defect, 1 when detected", summary["detections"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    parser.add_argument("manifest")
    parser.add_argument("work")
    parser.add_argument("--runs", type=int, default=3)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    planted = json.loads(Path(args.manifest).read_text())["planted"]
    work = Path(args.work).resolve()
    fixture = root / "integration" / "web_fixture"

    if args.runs < 1:
        fail("--runs must be at least 1")
    if not (fixture / "build" / "web" / "index.html").exists():
        fail("no fixture build at integration/web_fixture/build/web, run make run/web-fixture first")
    shutil.rmtree(work / "runs", ignore_errors=True)
    (work / "runs").mkdir(parents=True)
    config_path = work / "variance.yaml"
    config_path.write_text(
        json.dumps(config_for(fixture, work / "report", work), indent=2) + "\n"
    )
    config = str(config_path)
    started = datetime.now(timezone.utc)
    runs = []
    for index in range(1, args.runs + 1):
        entry = collect_once(root, config, work, planted, index)
        entry["loadAverage"] = round(os.getloadavg()[0], 1)
        runs.append(entry)
        print(
            f"run {index}/{args.runs}: {entry.get('failed', 'ok')}, load {entry['loadAverage']}",
            flush=True,
        )
    summary = summarize(planted, runs)
    result = {
        "started": started.isoformat(timespec="seconds"),
        "finished": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "machine": f"{platform.system()} {platform.machine()}, {os.cpu_count()} CPUs",
        "routes": ROUTES,
        **summary,
        "perRun": runs,
    }
    (work / "variance.json").write_text(json.dumps(result, indent=2) + "\n")
    print_summary(summary)
    print(f"wrote {work / 'variance.json'}")
    if summary["failedRuns"] == summary["runs"]:
        fail("every run failed")


if __name__ == "__main__":
    main()
