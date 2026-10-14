import copy
import json
from pathlib import Path

FIXTURE = Path(__file__).resolve().parents[2]
ROOT = FIXTURE.parents[1]


def load(path):
    return copy.deepcopy(json.loads(path.read_text()))


def performance():
    return load(FIXTURE / "performance.json")


def responsive():
    return load(FIXTURE / "responsive.json")


def planted():
    return load(FIXTURE / "planted.json")["planted"]


def e2e_report():
    return load(ROOT / "test" / "fixtures" / "e2e" / "expected" / "report.json")


def finding(source, rule, route, category="a11y", message="a defect", fingerprint=None):
    return {
        "fingerprint": fingerprint or f"{source}:{rule}:{route}:{message}",
        "source": source,
        "category": category,
        "rule": rule,
        "route": route,
        "message": message,
    }


def findings_for(entry):
    return [finding(source, entry["rule"], entry["route"], entry["category"]) for source in entry["sources"]]
