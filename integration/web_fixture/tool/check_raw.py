#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from urllib.parse import urlparse

report = Path(sys.argv[1])
routes = {"/account", "/public"}


def fail(message):
    raise SystemExit(message)


def route_paths(directory, url_key):
    files = sorted(path for path in directory.glob("*.json") if path.is_file())
    if len(files) != len(routes):
        fail(f"{directory} has {len(files)} json files, expected {len(routes)}")
    found = set()
    for path in files:
        data = json.loads(path.read_text())
        url = data[url_key]
        found.add(urlparse(url).path)
        if url_key != "finalDisplayedUrl":
            continue
        if data.get("requestedUrl") != url:
            fail(f"{path.name} requested URL differs from the final URL")
        if data.get("runtimeError") is not None:
            fail(f"{path.name} has a Lighthouse runtime error")
        settings = data["configSettings"]
        if settings.get("disableStorageReset") is not True:
            fail(f"{path.name} reset storage")
        if settings.get("formFactor") != "desktop":
            fail(f"{path.name} form factor is {settings.get('formFactor')}")
        screen = settings["screenEmulation"]
        if screen.get("mobile") is not False:
            fail(f"{path.name} used mobile screen emulation")
        if screen.get("width") != 1280 or screen.get("height") != 800:
            fail(f"{path.name} viewport is {screen.get('width')}x{screen.get('height')}")
        if screen.get("deviceScaleFactor") != 1:
            fail(f"{path.name} device scale is {screen.get('deviceScaleFactor')}")
    if found != routes:
        fail(f"{directory.name} routes were {sorted(found)}")


route_paths(report / "raw" / "lighthouse", "finalDisplayedUrl")
route_paths(report / "raw" / "axe", "url")

log = (report / "auth-backend.log").read_text().splitlines()
login_at = next((i for i, line in enumerate(log) if line == "POST /login 200"), None)
account_at = next((i for i, line in enumerate(log) if line == "GET /account 200"), None)
if login_at is None or account_at is None or account_at < login_at:
    fail("auth log did not show a real login before account access:\n" + "\n".join(log))
print("raw lighthouse and axe results match the authenticated routes")
