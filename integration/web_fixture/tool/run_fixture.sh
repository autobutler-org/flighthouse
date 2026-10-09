#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$root"
config="integration/web_fixture/flighthouse.yaml"
report="build/web-fixture"
rm -rf "$report"
mkdir -p "$report"
log="$root/$report/auth-backend.log"
rm -f "$log"

export FLIGHTHOUSE_USERNAME="${FLIGHTHOUSE_USERNAME:-fixture-user}"
export FLIGHTHOUSE_PASSWORD="${FLIGHTHOUSE_PASSWORD:-fixture-password}"
export FIXTURE_API_PORT="${FIXTURE_API_PORT:-8090}"
export FIXTURE_API_LOG="$log"

dart integration/web_fixture/tool/auth_backend.dart &
backend_pid=$!
cleanup() {
  kill "$backend_pid" >/dev/null 2>&1 || true
  wait "$backend_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 50); do
  if curl --silent --show-error --output /dev/null --request OPTIONS \
    "http://127.0.0.1:${FIXTURE_API_PORT}/login"; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" -ne 1 ]]; then
  echo "auth backend did not start" >&2
  exit 1
fi

dart run bin/flighthouse.dart --config "$config" collect
cp -a "$report/raw" "$report/raw-collected"
python3 integration/web_fixture/tool/check_raw.py "$report"
python3 integration/web_fixture/tool/check_gate.py "$root" "$config" "$report"
