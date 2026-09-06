#!/usr/bin/env bash
# scripts/release/appcast.sh <dist-dir> <version-tag>
#
# Generates (or regenerates a placeholder for) the Sparkle appcast, arch §9.4.
#
# Sparkle is listed as a Mac dependency "later" (CLAUDE.md conventions) — it is not wired into
# AirControlHelper yet. Until `UpdateService` exists, this script writes a well-formed but
# clearly-marked PLACEHOLDER appcast.xml so release.yml has something to publish to GitHub
# Pages without failing, and so the shape of the file is settled early.
#
# Once Sparkle is integrated and `SPARKLE_ED_PRIVATE_KEY` holds a real EdDSA private key, and
# the Sparkle `generate_appcast` tool is on PATH (it ships in the Sparkle distribution, not
# Homebrew — CI would need to `curl` it from the Sparkle release), this script signs for real.
#
# <dist-dir> must contain the release DMG named AirControl-<version-without-v>.dmg and its
# .sha256 sibling (produced by make-dmg.sh).
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <dist-dir> <version-tag>" >&2
  exit 1
fi

dist_dir="$1"
version_tag="$2"
version="${version_tag#v}"

dmg_path="$dist_dir/AirControl-${version}.dmg"
appcast_path="$dist_dir/appcast.xml"

if [ ! -f "$dmg_path" ]; then
  echo "error: expected DMG not found: $dmg_path" >&2
  exit 1
fi

dmg_size="$(stat -f%z "$dmg_path" 2>/dev/null || stat -c%s "$dmg_path")"
pub_date="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"
download_url="https://github.com/OWNER/air-control/releases/download/${version_tag}/$(basename "$dmg_path")"

if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ] && command -v generate_appcast >/dev/null 2>&1; then
  echo "Signing with Sparkle generate_appcast..."
  key_file="$(mktemp)"
  trap 'rm -f "$key_file"' EXIT
  printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$key_file"
  generate_appcast --ed-key-file "$key_file" -o "$appcast_path" "$dist_dir"
  echo "Wrote signed $appcast_path"
  exit 0
fi

echo "warning: SPARKLE_ED_PRIVATE_KEY or generate_appcast unavailable — writing PLACEHOLDER appcast" >&2

cat > "$appcast_path" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<!--
  PLACEHOLDER appcast — Sparkle is not yet integrated into AirControlHelper (see CLAUDE.md
  conventions and docs/00-decisions.md Addendum A6). The <enclosure> below has no valid
  sparkle:edSignature and MUST NOT be pointed to by a shipping SUFeedURL until UpdateService
  lands and generate_appcast is run for real. See scripts/release/appcast.sh.
-->
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>Air Control Changelog</title>
    <link>https://OWNER.github.io/air-control/appcast.xml</link>
    <item>
      <title>${version_tag}</title>
      <pubDate>${pub_date}</pubDate>
      <sparkle:version>${version}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${download_url}"
        length="${dmg_size}"
        type="application/octet-stream"
        sparkle:edSignature="PLACEHOLDER" />
    </item>
  </channel>
</rss>
EOF

echo "Wrote placeholder $appcast_path"
