#!/usr/bin/env bash
# Regenerates the landing page's static images from design/icons/*.png.
# macOS + Xcode only. CI never runs this — the generated PNGs are committed.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

swiftc -O -o "$tmp/make-assets" "$here/make-assets.swift"
"$tmp/make-assets" "$root"

# Small on-disk variants for images that only ever render at 16-28px (nav
# brand, hero device mock) plus the favicon — sips only, no new deps, so
# regeneration stays reproducible. The 384px masters above stay in public/
# for anything that still wants the larger source.
sips -Z 64 "$root/site/public/icon-ios.png" --out "$root/site/public/icon-ios-64.png" >/dev/null
sips -Z 64 "$root/site/public/icon-mac.png" --out "$root/site/public/icon-mac-64.png" >/dev/null
sips -Z 64 "$root/site/src/app/icon.png" >/dev/null
