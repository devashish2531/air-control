#!/usr/bin/env bash
# scripts/latency-rig/bench.sh — runs `airmouse-cli bench` against a real, already-paired Mac over
# Wi-Fi and appends one CSV row per run, for tracking the PRD/spec §8.1 latency metric
# (NFR-PERF-001: RTT p50 ≤ 12ms, p95 ≤ 20ms) over time. See README.md in this directory for the full
# procedure (ground truth camera rig, HUD correlation, jitter, reconnect).
#
# Usage:
#   scripts/latency-rig/bench.sh --host 192.168.1.23 [--port 47800] [--seconds 10] [--rate 120] \
#       [--fingerprint <hex>] [--out results.csv] [--label "living-room-5ghz"]
#
# Prerequisites: the Mac helper is running and this machine has already paired with it once
# (`airmouse-cli pair <airmouse://pair?...>` — scan/copy the URL from the helper's pairing window).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
KIT_DIR="$REPO_ROOT/Packages/AirMouseKit"

HOST=""
PORT="47800"
SECONDS_ARG="10"
RATE="120"
FINGERPRINT=""
OUT="$SCRIPT_DIR/results.csv"
LABEL="$(date +%Y%m%dT%H%M%S)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --seconds) SECONDS_ARG="$2"; shift 2 ;;
    --rate) RATE="$2"; shift 2 ;;
    --fingerprint) FINGERPRINT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    -h|--help)
      cat <<'USAGE'
bench.sh — run `airmouse-cli bench` against a real Mac over Wi-Fi and record one CSV row.

Usage:
  bench.sh --host <ip> [--port 47800] [--seconds 10] [--rate 120] \
            [--fingerprint <hex>] [--out results.csv] [--label <name>]

Prerequisites: the Mac helper is running and this machine has already paired with it once
(`airmouse-cli pair <airmouse://pair?...>`). See README.md in this directory for the full procedure.
USAGE
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "error: --host is required (the Mac's Wi-Fi IP address)" >&2
  exit 1
fi

FP_ARGS=()
if [[ -n "$FINGERPRINT" ]]; then
  FP_ARGS=(--fingerprint "$FINGERPRINT")
fi

echo "Building airmouse-cli (release, for a representative measurement)…" >&2
(cd "$KIT_DIR" && swift build -c release --scratch-path .build/latency-rig --product airmouse-cli) >&2

BIN="$KIT_DIR/.build/latency-rig/release/airmouse-cli"

echo "Running: $BIN bench --host $HOST --port $PORT --seconds $SECONDS_ARG --rate $RATE --json" >&2
JSON_OUT="$("$BIN" bench --host "$HOST" --port "$PORT" --seconds "$SECONDS_ARG" --rate "$RATE" "${FP_ARGS[@]}" --json)"
echo "$JSON_OUT" >&2

if [[ ! -f "$OUT" ]]; then
  echo "timestamp,label,host,rate_hz,seconds,rtt_p50_ms,rtt_p95_ms,loss_percent,motion_rate_per_second,fallback_engaged" > "$OUT"
fi

# Pull fields out of the bench --json payload with plain shell tools (no jq dependency assumed).
extract() {
  echo "$JSON_OUT" | sed -E "s/.*\"$1\":([^,}]*).*/\\1/" | tr -d '"'
}

RTT_P50="$(extract rttP50Ms)"
RTT_P95="$(extract rttP95Ms)"
LOSS="$(extract lossPercent)"
MOTION_RATE="$(extract motionRatePerSecond)"
FALLBACK="$(extract fallbackEngaged)"

echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$LABEL,$HOST,$RATE,$SECONDS_ARG,$RTT_P50,$RTT_P95,$LOSS,$MOTION_RATE,$FALLBACK" >> "$OUT"

echo "Appended one row to $OUT" >&2
echo "  rtt p50=${RTT_P50}ms p95=${RTT_P95}ms loss=${LOSS}% motion/s=${MOTION_RATE} fallback=${FALLBACK}" >&2

# spec §8.1 NFR-PERF-001: control-path RTT p50 ≤ 12ms, p95 ≤ 20ms. This is the heartbeat RTT, not the
# camera-measured end-to-end motion latency (README.md §"What this does NOT measure") — treat a red
# result here as a strong signal, not the final pass/fail number for that requirement.
if awk -v p50="$RTT_P50" 'BEGIN { exit !(p50 > 12) }' 2>/dev/null; then
  echo "warning: rtt p50 ${RTT_P50}ms exceeds the 12ms NFR-PERF-001 target" >&2
fi
if awk -v p95="$RTT_P95" 'BEGIN { exit !(p95 > 20) }' 2>/dev/null; then
  echo "warning: rtt p95 ${RTT_P95}ms exceeds the 20ms NFR-PERF-001 target" >&2
fi
