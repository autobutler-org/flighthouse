#!/usr/bin/env bash
# One-command flighthouse run against a real local Quark (#166).
#
#   tool/e2e_quark/e2e.sh all          bring up, seed, build web, collect, report, ci, tear down
#   tool/e2e_quark/e2e.sh <step>       quark-up | seed | web | collect | report | ci | quark-down
#
# Every input is an environment variable; AGENTS.md ("End-to-end run against Quark") lists them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUARK_VERSION="${QUARK_VERSION:-v0.50.1}"
QUARK_REPO="${QUARK_REPO:-autobutler-org/quark}"
PORT="${PORT:-18531}"
WORK_DIR="$(mkdir -p "${WORK_DIR:-$ROOT/.flighthouse/e2e-quark}" && cd "${WORK_DIR:-$ROOT/.flighthouse/e2e-quark}" && pwd)"
CACHE="$WORK_DIR/cache"
QUARK_HOME="$WORK_DIR/quark-home"
PID_FILE="$WORK_DIR/quark.pid"
CREDENTIALS="${CREDENTIALS:-$WORK_DIR/credentials.env}"
SEED_SCALE="${SEED_SCALE:-6}"
# The seeded data changes what /photos shows, so each household size keeps its own baseline.
BASELINE="${BASELINE:-$WORK_DIR/flighthouse-baseline-$QUARK_VERSION-scale$SEED_SCALE.json}"
KEEP="${KEEP:-0}"
FLUTTER="${FLUTTER:-flutter}"
EXTERNAL=0
if [ -n "${QUARK_URL:-}" ]; then EXTERNAL=1; else QUARK_URL="http://127.0.0.1:$PORT"; fi
RUN_DIR="${RUN_DIR:-$WORK_DIR/runs/current}"
mkdir -p "$CACHE" "$RUN_DIR/logs"

log() { printf 'e2e-quark: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

quark_bin() {
  if [ -n "${QUARK_BIN:-}" ]; then echo "$QUARK_BIN"; return; fi
  local arch
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) arch=x86_64 ;;
    Linux-aarch64 | Linux-arm64) arch=arm64 ;;
    *) die "no Quark release binary for $(uname -s)-$(uname -m); set QUARK_BIN" ;;
  esac
  local dir="$CACHE/quark-$QUARK_VERSION" tarball="quark_Linux_${arch}.tar.gz"
  if [ ! -x "$dir/quark" ]; then
    local base="https://github.com/$QUARK_REPO/releases/download/$QUARK_VERSION"
    local version="${QUARK_VERSION#v}"
    mkdir -p "$dir"
    log "downloading Quark $QUARK_VERSION ($tarball)"
    curl -fsSL -o "$dir/$tarball" "$base/$tarball"
    curl -fsSL -o "$dir/checksums.txt" "$base/quark_${version}_checksums.txt"
    (cd "$dir" && grep " $tarball\$" checksums.txt | sha256sum -c --quiet -) || die "checksum mismatch for $tarball"
    tar -xzf "$dir/$tarball" -C "$dir"
  fi
  echo "$dir/quark"
}

step_quark_up() {
  if [ "$EXTERNAL" = 1 ]; then log "using the running Quark at $QUARK_URL"; return; fi
  if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "Quark already up (pid $(cat "$PID_FILE")) at $QUARK_URL"; return
  fi
  if curl -fs "$QUARK_URL/api/v0/auth/status" >/dev/null 2>&1; then
    die "something already answers on $QUARK_URL; pick another PORT or set QUARK_URL to use it"
  fi
  local bin; bin="$(quark_bin)"
  mkdir -p "$QUARK_HOME"
  HOME="$QUARK_HOME" PORT="$PORT" QUARK_INSECURE=true nohup "$bin" serve >"$RUN_DIR/logs/quark.log" 2>&1 &
  echo $! >"$PID_FILE"
  for _ in $(seq 120); do
    if curl -fs "$QUARK_URL/api/v0/auth/status" >/dev/null 2>&1; then
      log "Quark $QUARK_VERSION up at $QUARK_URL (pid $(cat "$PID_FILE"), HOME $QUARK_HOME)"; return
    fi
    kill -0 "$(cat "$PID_FILE")" 2>/dev/null || break
    sleep 0.5
  done
  tail -20 "$RUN_DIR/logs/quark.log" >&2 || true
  die "Quark did not answer on $QUARK_URL"
}

step_seed() {
  QUARK_URL="$QUARK_URL" QUARK_BIN="$(quark_bin)" CREDENTIALS="$CREDENTIALS" \
    STATE="$WORK_DIR/seed-state-$(echo "$QUARK_URL" | tr -c 'a-zA-Z0-9' _)" SEED_SCALE="$SEED_SCALE" \
    dart run "$ROOT/tool/e2e_quark/seed.dart"
}

web_dir() { echo "$CACHE/web-$QUARK_VERSION"; }

step_web() {
  local out; out="$(web_dir)"
  if [ -f "$out/index.html" ]; then log "reusing the cached web build $out"; return; fi
  local src="${QUARK_SRC:-$CACHE/quark-src-$QUARK_VERSION}"
  if [ ! -d "$src" ]; then
    log "cloning $QUARK_REPO at $QUARK_VERSION"
    git clone -q --depth 1 -b "$QUARK_VERSION" "https://github.com/$QUARK_REPO.git" "$src"
  fi
  local want have
  want="$(sed -n 's/^  flutter: *//p' "$src/pubspec.yaml" | head -1)"
  have="$("$FLUTTER" --version 2>/dev/null | sed -n 's/^Flutter \([0-9.]*\).*/\1/p')"
  if [ -n "$want" ] && [ "$want" != "$have" ]; then
    die "Quark $QUARK_VERSION pins Flutter $want but FLUTTER ($FLUTTER) is ${have:-missing}; set FLUTTER to a $want flutter binary"
  fi
  log "building Quark web with Flutter $have (about 90 s and several GB of RAM)"
  (cd "$src" && PATH="$(dirname "$(command -v "$FLUTTER")"):$PATH" make build/frontend/web FLUTTER_BUILD_MODE=release)
  rm -rf "$out.tmp" && cp -R "$src/build/web" "$out.tmp" && mv "$out.tmp" "$out"
}

write_config() {
  local out; out="$(web_dir)"
  sed -e "s#^reportDir:.*#reportDir: $RUN_DIR/report#" \
    -e "s#^baseline:.*#baseline: $BASELINE#" \
    -e "s#^  projectDir:.*#  projectDir: $(dirname "$out")#" \
    -e "s#^    outputDir:.*#    outputDir: $(basename "$out")#" \
    -e "/^    command:\$/,/^    outputDir:/{/^    command:\$/c\\    command: ['true']
/^      - /d}" \
    "$ROOT/test/fixtures/quark/d8d2618e/collect.yaml" >"$RUN_DIR/collect.yaml"
}

flighthouse() { dart run "$ROOT/bin/flighthouse.dart" --config "$RUN_DIR/collect.yaml" "$@"; }

step_collect() {
  [ -f "$CREDENTIALS" ] || die "no credentials at $CREDENTIALS; run the seed step first"
  write_config
  set -a; source "$CREDENTIALS"; set +a
  flighthouse collect
}

step_report() { flighthouse report; }

step_ci() {
  if [ ! -f "$BASELINE" ]; then
    log "no baseline at $BASELINE: accepting this run as the baseline (first run)"
    flighthouse baseline --update
  fi
  flighthouse ci
}

step_quark_down() {
  if [ "$EXTERNAL" = 1 ]; then return 0; fi
  if [ -f "$PID_FILE" ]; then
    local pid; pid="$(cat "$PID_FILE")"
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    log "stopped Quark (pid $pid)"
  fi
  if [ "${1:-}" = wipe ]; then
    rm -rf "$QUARK_HOME" "$WORK_DIR"/seed-state-* "$CREDENTIALS"
    log "removed the Quark data dir and its credentials"
  fi
  return 0
}

# Runs one step, logs it to $RUN_DIR/logs/<step>.log, and appends name, exit code, seconds to steps.tsv.
run_step() {
  local name="$1" start end code=0
  start="$(date +%s.%N)"
  "step_${name//-/_}" > >(tee "$RUN_DIR/logs/$name.log") 2>&1 || code=$?
  end="$(date +%s.%N)"
  printf '%s\t%s\t%s\n' "$name" "$code" "$(awk "BEGIN{printf \"%.1f\", $end-$start}")" >>"$RUN_DIR/steps.tsv"
  return "$code"
}

exit_code_for() {
  case "$1" in
    quark-up) echo 10 ;; seed) echo 11 ;; web) echo 12 ;; collect) echo 13 ;; report) echo 14 ;;
  esac
}

all() {
  rm -rf "$RUN_DIR" && mkdir -p "$RUN_DIR/logs"
  local code=0 failed=""
  # shellcheck disable=SC2329
  finish() {
    if [ "$KEEP" != 1 ]; then step_quark_down wipe; else log "KEEP=1: Quark left running at $QUARK_URL"; fi
    dart run "$ROOT/tool/e2e_quark/summary.dart" "$RUN_DIR" "$code" \
      "{\"quark\":\"$QUARK_VERSION\",\"flighthouse\":\"$(sed -n 's/^version: //p' "$ROOT/pubspec.yaml")\",\"seedScale\":$SEED_SCALE}" || true
    log "summary: $RUN_DIR/summary.json"
  }
  trap 'code=130; exit 130' INT TERM
  trap finish EXIT
  for s in quark-up seed web collect report; do
    if ! run_step "$s"; then failed="$s"; break; fi
  done
  if [ -n "$failed" ]; then
    code="$(exit_code_for "$failed")"
    log "step $failed failed; see $RUN_DIR/logs/$failed.log"
  else
    run_step ci || code=$?
  fi
  exit "$code"
}

case "${1:-}" in
  all) all ;;
  quark-up | seed | web | collect | report | ci) run_step "$1" ;;
  quark-down) step_quark_down "${2:-}" ;;
  *) sed -n '2,8p' "$0" >&2; exit 2 ;;
esac
