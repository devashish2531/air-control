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
