#!/usr/bin/env bash
# One-time contributor setup. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
if ! command -v xcodegen >/dev/null && [ ! -x tools/bin/xcodegen ]; then
  echo "Fetching XcodeGen binary…"
  mkdir -p tools/bin && tmp=$(mktemp -d)
  curl -sL -o "$tmp/xcodegen.zip" https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
  (cd "$tmp" && unzip -qo xcodegen.zip) && cp "$tmp/xcodegen/bin/xcodegen" tools/bin/ && rm -rf "$tmp"
fi
[ -f Config/Local.xcconfig ] || cp Config/Local.xcconfig.example Config/Local.xcconfig
make gen
echo "Done. Try: make kit-test && make build"
