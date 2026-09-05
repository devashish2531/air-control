#!/usr/bin/env bash
# scripts/release/make-dmg.sh <path/to/AppName.app> <path/to/output.dmg>
#
# Builds a notarization-friendly DMG with `create-dmg` (installed via scripts/Brewfile in CI).
# The .app passed in should already be notarized and stapled (see notarize.sh) — the DMG itself
# does not need separate notarization as long as the .app inside carries a valid staple.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <path/to/AppName.app> <path/to/output.dmg>" >&2
  exit 1
fi

app_path="$1"
dmg_path="$2"

if [ ! -d "$app_path" ]; then
  echo "error: not a directory: $app_path" >&2
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "error: create-dmg not found on PATH (brew install create-dmg)" >&2
  exit 1
fi

mkdir -p "$(dirname "$dmg_path")"
rm -f "$dmg_path"

app_name="$(basename "$app_path" .app)"
volume_name="Air Mouse"

echo "Creating DMG at $dmg_path from $app_path"
create-dmg \
  --volname "$volume_name" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "$(basename "$app_path")" 180 190 \
  --hide-extension "$(basename "$app_path")" \
  --app-drop-link 480 190 \
  "$dmg_path" \
  "$app_path" \
  || {
    # create-dmg returns non-zero if the volume icon/background assets are missing;
    # fall back to a minimal DMG so releases are never blocked on cosmetics.
    echo "warning: create-dmg failed with styling options, retrying minimal" >&2
    hdiutil create -volname "$volume_name" -srcfolder "$app_path" -ov -format UDZO "$dmg_path"
  }

echo "Wrote $dmg_path"
