#!/usr/bin/env bash
# Regenerates the gallery's web-sized screenshots from the 1206x2622 masters
# in design/screenshots/. macOS (sips) only. CI never runs this — the
# generated PNGs are committed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

src="$root/design/screenshots"
out="$here/../public/screenshots"
mkdir -p "$out"

# slug:mode -> source file (relative to design/screenshots/)
declare -a map=(
  "touchpad:light:IMG_3966.PNG"
  "touchpad:dark:IMG_3972.PNG"
  "air-pointer:light:IMG_3967 2.PNG"
  "air-pointer:dark:IMG_3973.PNG"
  "keyboard:light:IMG_3968 2.PNG"
  "keyboard:dark:IMG_3975.PNG"
  "remote:light:IMG_3969 2.PNG"
  "remote:dark:IMG_3976.PNG"
  "macros:light:IMG_3970 2.PNG"
  "macros:dark:IMG_3977.PNG"
  "settings:light:IMG_3971 2.PNG"
  "settings:dark:IMG_3978.PNG"
)

for entry in "${map[@]}"; do
  slug="${entry%%:*}"; rest="${entry#*:}"
  mode="${rest%%:*}"; file="${rest#*:}"
  in="$src/$file"
  if [[ ! -f "$in" ]]; then
    echo "missing source: $in" >&2
    exit 1
  fi
  for width in 480 960; do
    sips --resampleWidth "$width" "$in" --out "$out/$slug-$mode-$width.png" >/dev/null
  done
done

echo "Wrote $(ls "$out" | wc -l | tr -d ' ') files to $out"
