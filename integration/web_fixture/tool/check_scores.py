#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path


def fail(message):
    raise SystemExit(message)


def config_for(route, fixture, report, work):
    return {
        "app": "web-fixture-scores",
        "reportDir": str(report),
        "baseline": str(work / "flighthouse-baseline.json"),
        "web": {
            "projectDir": str(fixture),
            "build": {"command": ["true"], "outputDir": "build/web"},
            "serve": {"port": 0},
            "routes": [route],
            "readiness": {"timeoutSeconds": 90, "selector": '[role="main"]'},
            "viewport": {"width": 1280, "height": 800, "deviceScaleFactor": 1},
            "lighthouse": {"command": ["lighthouse"]},
            "axe": {"version": "4.11.1"},
        },
    }


def category_score(data, category, route):
    score = data["scores"]["categories"].get(category)
    if score is None:
        fail(f"{route} has no {category} score in report.json")
    return round(score, 4)


def gate_failures(clean, planted, margin):
    if planted > round(clean - margin, 4):
        return [f"planted scored {planted}, not at least {margin} below clean at {clean}"]
    return []


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


def collected_score(root, fixture, work, route, category):
    report = work / "report"
    work.mkdir(parents=True, exist_ok=True)
    config_path = work / "scores.yaml"
    config_path.write_text(json.dumps(config_for(route, fixture, report, work), indent=2) + "\n")
    config = str(config_path)
    run(root, config, "collect")
    run(root, config, "report")
    return category_score(json.loads((report / "report.json").read_text()), category, route)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    parser.add_argument("manifest")
    parser.add_argument("work")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    manifest = json.loads(Path(args.manifest).read_text())
    work = Path(args.work).resolve()
    fixture = root / "integration" / "web_fixture"
    category = manifest["category"]

    clean = collected_score(root, fixture, work / "clean", manifest["clean"], category)
    print(f"{manifest['clean']}: {category} {clean}")
    planted = collected_score(root, fixture, work / "planted", manifest["planted"], category)
    print(f"{manifest['planted']}: {category} {planted}")
    failures = gate_failures(clean, planted, manifest["margin"])
    if failures:
        fail("\n".join(failures))
    print(f"planted scores {round(clean - planted, 4)} below clean, at least the margin {manifest['margin']}")


if __name__ == "__main__":
    main()
