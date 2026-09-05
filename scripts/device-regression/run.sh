#!/usr/bin/env bash
# On-device regression orchestrator (Mac side). Builds + launches the Mac helper against a real
# code-signing identity, opens a fresh TextEdit document, runs the AirMouseUITests
# `DeviceRegressionUITests` suite on an already-paired iPhone, then verifies the touchpad actually
# moved the host cursor, the keyboard test's text actually arrived in TextEdit, and the helper's
# own host log shows a clean authenticated session. Prints a PASS/FAIL table and always cleans up
# the helper process + log stream, even on failure.
#
# Usage: scripts/device-regression/run.sh
# Requires: DEVELOPER_DIR set to a real Xcode.app, the phone already paired/trusted, and
# apps/AirMouse-iOS/AirMouse.xcodeproj already built-for-testing at least once (this script calls
# `xcodebuild test-without-building`, not `test`, per the coordinator's per-invocation overhead
# note -- run `make gen` + a `build-for-testing` invocation first if DerivedData is empty).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

UDID="0A51118F-A890-52B2-84DF-CEFB294F0694"
PROJECT="apps/AirMouse-iOS/AirMouse.xcodeproj"
SCHEME="AirMouse"
SUITE="AirMouseUITests/DeviceRegressionUITests"
ENTITLEMENTS="apps/AirMouse-Mac/Sources/AirMouseHelper.entitlements"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/airmouse-device-regression.XXXXXX")"
HELPER_LOG="$WORKDIR/helper.out"
HOST_LOG="$WORKDIR/host.log"
TEST_LOG="$WORKDIR/xcodebuild-test.log"

HELPER_PID=""
LOGSTREAM_PID=""

cleanup() {
    if [ -n "$LOGSTREAM_PID" ]; then kill "$LOGSTREAM_PID" >/dev/null 2>&1 || true; fi
    if [ -n "$HELPER_PID" ]; then kill "$HELPER_PID" >/dev/null 2>&1 || true; fi
    pkill -f "AirMouse.app/Contents/MacOS/AirMouse" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== [1/8] Waiting for port 47800 / any Mac helper test run to be free =="
deadline=$((SECONDS + 900))
while lsof -nP -iTCP:47800 -sTCP:LISTEN >/dev/null 2>&1 || pgrep -f "xcodebuild.*AirMouseHelper" >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
        echo "Timed out after 15 min waiting for port 47800 / helper test run to finish" >&2
        exit 1
    fi
    sleep 30
done

echo "== [2/8] Building Mac helper (make mac-build) =="
if ! make -C "$REPO_DIR" mac-build > "$WORKDIR/mac-build.log" 2>&1; then
    echo "make mac-build failed; see $WORKDIR/mac-build.log" >&2
    tail -60 "$WORKDIR/mac-build.log" >&2
    exit 1
fi

APP="$(ls -d "$HOME/Library/Developer/Xcode/DerivedData/AirMouseHelper-"*/Build/Products/Debug/AirMouse.app 2>/dev/null | head -1)"
if [ -z "$APP" ]; then
    echo "AirMouse.app not found in DerivedData after mac-build" >&2
    exit 1
fi
ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"')"
if [ -z "$ID" ]; then
    echo "No 'Apple Development' codesigning identity found" >&2
    exit 1
fi

echo "== [3/8] Signing + (re)launching helper: $APP =="
codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" --sign "$ID" "$APP"
pkill -f "AirMouse.app/Contents/MacOS/AirMouse" >/dev/null 2>&1 || true
sleep 1

log stream --predicate 'process == "AirMouse" AND subsystem == "com.airmouse.helper"' --level debug --style compact > "$HOST_LOG" 2>&1 &
LOGSTREAM_PID=$!
sleep 2

AIRMOUSE_PAIR_SECRET_TTL=900 nohup "$APP/Contents/MacOS/AirMouse" --print-pair-url --log-level debug > "$HELPER_LOG" 2>&1 &
HELPER_PID=$!
sleep 2
if ! kill -0 "$HELPER_PID" >/dev/null 2>&1; then
    echo "Helper process exited immediately; see $HELPER_LOG" >&2
    cat "$HELPER_LOG" >&2
    exit 1
fi

echo "== [4/8] Preparing TextEdit (fresh document) =="
osascript \
    -e 'tell application "TextEdit" to activate' \
    -e 'tell application "TextEdit" to make new document' \
    -e 'delay 0.5' \
    -e 'tell application "TextEdit" to set bounds of front window to {0, 0, 1400, 900}' \
    >/dev/null 2>&1 || true

CURSOR_BEFORE="$(swift -e 'import CoreGraphics; print(CGEvent(source: nil)!.location)' 2>/dev/null || true)"

echo "== [5/8] Running device UI test suite: $SUITE =="
xcodebuild test-without-building \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "id=$UDID" \
    -only-testing:"$SUITE" \
    > "$TEST_LOG" 2>&1
TEST_EXIT=$?

echo "== [6/8] Reading back Mac-side state =="
CURSOR_AFTER="$(swift -e 'import CoreGraphics; print(CGEvent(source: nil)!.location)' 2>/dev/null || true)"
TEXTEDIT_TEXT="$(osascript -e 'tell application "TextEdit" to get text of document 1' 2>/dev/null || true)"

parse_x() { printf '%s' "$1" | sed -nE 's/^\(([0-9.-]+), *([0-9.-]+)\)$/\1/p'; }

echo "== [7/8] Verifying =="
X_BEFORE="$(parse_x "$CURSOR_BEFORE")"
X_AFTER="$(parse_x "$CURSOR_AFTER")"
DELTA_X="n/a"
TOUCHPAD_RESULT="FAIL"
if [[ "$X_BEFORE" =~ ^-?[0-9.]+$ ]] && [[ "$X_AFTER" =~ ^-?[0-9.]+$ ]]; then
    DELTA_X="$(awk -v a="$X_AFTER" -v b="$X_BEFORE" 'BEGIN{printf "%.1f", a-b}')"
    if awk -v d="$DELTA_X" 'BEGIN{exit !(d>=40)}'; then TOUCHPAD_RESULT="PASS"; fi
fi

KEYBOARD_RESULT="FAIL"
if printf '%s' "$TEXTEDIT_TEXT" | grep -q "airmouse ok"; then KEYBOARD_RESULT="PASS"; fi

SESSION_AUTH_RESULT="FAIL"
grep -q "session authenticated" "$HOST_LOG" 2>/dev/null && SESSION_AUTH_RESULT="PASS"

HELPER_ERROR_LINES="$(grep -i "error" "$HOST_LOG" "$HELPER_LOG" 2>/dev/null || true)"
NO_ERRORS_RESULT="PASS"
[ -n "$HELPER_ERROR_LINES" ] && NO_ERRORS_RESULT="FAIL"

UITEST_RESULT="FAIL"
[ "$TEST_EXIT" -eq 0 ] && UITEST_RESULT="PASS"

echo "== [8/8] PASS/FAIL table =="
printf '%-42s %s\n' "xcodebuild UI test suite" "$UITEST_RESULT"
printf '%-42s %s\n' "Touchpad: cursor moved right >= 40px" "$TOUCHPAD_RESULT (dx=$DELTA_X, before=$CURSOR_BEFORE, after=$CURSOR_AFTER)"
printf '%-42s %s\n' "Keyboard: 'airmouse ok' arrived in TextEdit" "$KEYBOARD_RESULT"
printf '%-42s %s\n' "Host log: session authenticated" "$SESSION_AUTH_RESULT"
printf '%-42s %s\n' "Host log: no 'error' lines from helper" "$NO_ERRORS_RESULT"

echo
echo "Work dir:            $WORKDIR"
echo "xcodebuild test log: $TEST_LOG"
echo "helper stdout:       $HELPER_LOG"
echo "host log:            $HOST_LOG"

if [ -n "$HELPER_ERROR_LINES" ]; then
    echo
    echo "-- helper/host 'error' lines --"
    printf '%s\n' "$HELPER_ERROR_LINES"
fi

if [ "$UITEST_RESULT" = "FAIL" ]; then
    echo
    echo "-- xcodebuild failure summary (last 40 lines) --"
    tail -40 "$TEST_LOG"
fi

OVERALL="PASS"
for r in "$UITEST_RESULT" "$TOUCHPAD_RESULT" "$KEYBOARD_RESULT" "$SESSION_AUTH_RESULT" "$NO_ERRORS_RESULT"; do
    [ "$r" = "PASS" ] || OVERALL="FAIL"
done
echo
echo "OVERALL: $OVERALL"
[ "$OVERALL" = "PASS" ]
