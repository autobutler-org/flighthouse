#!/usr/bin/env python3
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
config = sys.argv[2]
report = Path(sys.argv[3])
baseline = report / "flighthouse-baseline.json"


def fail(message):
    raise SystemExit(message)


def run(args):
    completed = subprocess.run(
        ["dart", "run", "bin/flighthouse.dart", "--config", config, *args],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    return completed


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


update = run(["baseline", "--update"])
if update.returncode != 0:
    sys.stderr.write(update.stdout + update.stderr)
    fail(f"baseline --update exited {update.returncode}")
clean = digest(baseline)

passed = run(["ci"])
if passed.returncode != 0 or "gate passed" not in passed.stdout:
    sys.stderr.write(passed.stdout + passed.stderr)
    fail(f"clean ci exited {passed.returncode}")

axe_file = next((report / "raw" / "axe").glob("*.json"))
data = json.loads(axe_file.read_text())
data["violations"].append(
    {
        "id": "button-name",
        "impact": "serious",
        "help": "Buttons must have discernible text",
        "nodes": [
            {
                "html": '<button id="flighthouse-intentional">',
                "impact": "serious",
                "target": ["#flighthouse-intentional-new-finding"],
                "ancestry": ["flutter-view > #flighthouse-intentional-new-finding"],
            }
        ],
    }
)
axe_file.write_text(json.dumps(data))
serious = run(["ci"])
if serious.returncode != 1:
    sys.stderr.write(serious.stdout + serious.stderr)
    fail(f"new serious finding exited {serious.returncode}, expected 1")
if digest(baseline) != clean:
    fail("ci rewrote the baseline after a new finding")

axe_file.write_text("{")
before = digest(baseline)
invalid_ci = run(["ci"])
if invalid_ci.returncode != 3 or "not evaluated" not in invalid_ci.stderr:
    sys.stderr.write(invalid_ci.stdout + invalid_ci.stderr)
    fail(f"invalid ci exited {invalid_ci.returncode}")
if digest(baseline) != before:
    fail("invalid ci updated the baseline")

invalid_update = run(["baseline", "--update"])
if invalid_update.returncode != 3 or "not touched" not in invalid_update.stderr:
    sys.stderr.write(invalid_update.stdout + invalid_update.stderr)
    fail(f"invalid baseline --update exited {invalid_update.returncode}")
if digest(baseline) != before:
    fail("invalid baseline --update changed the baseline")

print("gate rejects a new serious finding and invalid tool JSON")
