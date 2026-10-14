#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

CATEGORIES = ["a11y", "perf", "responsiveness", "memory", "best-practices"]


def fail(message):
    raise SystemExit(message)


def overflowing_route(manifest):
    return next(entry["route"] for entry in manifest["routes"] if entry["overflows"])


def config_for(viewport, fixture, work, routes):
    name = viewport["name"]
    return {
        "app": f"web-fixture-responsive-{name}",
        "reportDir": str(work / name),
        "baseline": str(work / name / "flighthouse-baseline.json"),
        "web": {
            "projectDir": str(fixture),
            "build": {"command": ["true"], "outputDir": "build/web"},
            "serve": {"port": 0},
            "routes": routes,
            "readiness": {"timeoutSeconds": 90, "selector": '[role="main"]'},
            "viewport": {
                "width": viewport["width"],
                "height": viewport["height"],
                "deviceScaleFactor": 1,
            },
            "lighthouse": {"command": ["lighthouse"]},
            "axe": {"version": "4.11.1"},
        },
    }


def observation(viewport, data, routes):
    findings = {
        route: {
            category: sum(
                1
                for finding in data["findings"]
                if finding["route"] == route and finding["category"] == category
            )
            for category in CATEGORIES
        }
        for route in routes
    }
    return {
        "width": viewport["width"],
        "responsivenessScore": data["scores"]["categories"]["responsiveness"],
        "findings": findings,
        "lighthouse": data["metadata"]["toolVersions"]["lighthouse"],
    }


def difference(manifest, observed):
    overflowing = overflowing_route(manifest)
    wide, narrow = (observed[viewport["name"]] for viewport in manifest["viewports"])
    return (
        narrow["findings"][overflowing]["responsiveness"]
        - wide["findings"][overflowing]["responsiveness"]
    )


def summary(observed):
    return {
        name: {key: value for key, value in run.items() if key != "lighthouse"}
        for name, run in observed.items()
    }


def responsiveness(runs, routes):
    return {
        name: (
            run["responsivenessScore"],
            {route: run["findings"][route]["responsiveness"] for route in routes},
        )
        for name, run in runs.items()
    }


def matches_recorded(manifest, observed):
    routes = [entry["route"] for entry in manifest["routes"]]
    return responsiveness(summary(observed), routes) == responsiveness(
        manifest["observed"], routes
    )


def recorded_manifest(manifest, observed, recorded):
    return {
        **manifest,
        "recorded": recorded,
        "observed": summary(observed),
        "difference": difference(manifest, observed),
    }


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    parser.add_argument("manifest")
    parser.add_argument("work")
    parser.add_argument("--record", action="store_true")
    parser.add_argument("--machine")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    manifest_path = Path(args.manifest).resolve()
    manifest = json.loads(manifest_path.read_text())
    work = Path(args.work).resolve()
    fixture = root / "integration" / "web_fixture"
    routes = [entry["route"] for entry in manifest["routes"]]

    def observe(viewport):
        path = work / f"{viewport['name']}.yaml"
        config = config_for(viewport, fixture, work, routes)
        path.write_text(json.dumps(config, indent=2) + "\n")
        run(root, str(path), "collect")
        run(root, str(path), "report")
        data = json.loads((work / viewport["name"] / "report.json").read_text())
        return observation(viewport, data, routes)

    work.mkdir(parents=True, exist_ok=True)
    observed = {viewport["name"]: observe(viewport) for viewport in manifest["viewports"]}
    for name, run_ in observed.items():
        print(f"{name} ({run_['width']}px): responsiveness score {run_['responsivenessScore']}")
        for route in routes:
            print(f"  {route}: findings by category {run_['findings'][route]}")
    print(
        f"{overflowing_route(manifest)} responsiveness findings, narrow minus wide: "
        f"{difference(manifest, observed)} (recorded {manifest['difference']})"
    )

    if args.record:
        recorded = {
            "date": date.today().isoformat(),
            "machine": args.machine or manifest["recorded"]["machine"],
            "lighthouse": next(iter(observed.values()))["lighthouse"],
        }
        updated = recorded_manifest(manifest, observed, recorded)
        manifest_path.write_text(json.dumps(updated, indent=2) + "\n")
        print(f"recorded to {manifest_path}")
    elif not matches_recorded(manifest, observed):
        fail(
            "flighthouse reports the responsive routes differently than "
            f"{manifest_path.name} recorded; if it gained a layout signal, "
            f"re-record and close {manifest['gap']}"
        )


if __name__ == "__main__":
    main()
