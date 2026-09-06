#!/usr/bin/env bash
#
# gen-icons.sh — regenerate every app-icon asset, end to end.
#
# Step 1 draws the three 1024x1024 source images in design/icons as vector
# shapes (scripts/icon-tools/IconDraw.swift); step 2 turns them into the two
# AppIcon.appiconsets (scripts/icon-tools/IconTool.swift). Idempotent: it
# rewrites the sources, the generated PNGs and both Contents.json from scratch.
#
# See design/icons/README.md for the crop/mask rules this implements.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IOS_SOURCE="$ROOT/design/icons/ios-icon-source.png"
IOS_DARK_SOURCE="$ROOT/design/icons/ios-icon-source-dark.png"
MAC_SOURCE="$ROOT/design/icons/mac-icon-source.png"
IOS_SET="$ROOT/apps/AirControl-iOS/Resources/Assets.xcassets/AppIcon.appiconset"
MAC_SET="$ROOT/apps/AirControl-Mac/Resources/Assets.xcassets/AppIcon.appiconset"
TOOL_SOURCE="$ROOT/scripts/icon-tools/IconTool.swift"
DRAW_SOURCE="$ROOT/scripts/icon-tools/IconDraw.swift"

for f in "$TOOL_SOURCE" "$DRAW_SOURCE"; do
  [[ -f "$f" ]] || { echo "gen-icons: missing $f" >&2; exit 1; }
done
mkdir -p "$IOS_SET" "$MAC_SET"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> building the icon tools"
swiftc -O -o "$WORK/icondraw" "$DRAW_SOURCE"
swiftc -O -o "$WORK/icontool" "$TOOL_SOURCE"
DRAW="$WORK/icondraw"
TOOL="$WORK/icontool"

echo "==> drawing the sources"
# Vector artwork, 1024x1024, full-bleed and opaque: no baked corner radius, no
# white margin. The masks and the macOS body shape are applied downstream.
"$DRAW" ios "$IOS_SOURCE"
"$DRAW" ios-dark "$IOS_DARK_SOURCE"
"$DRAW" mac "$MAC_SOURCE"

echo "==> iOS icons"
rm -f "$IOS_SET"/*.png
# The sources are already edge-to-edge artwork, so nothing is cropped away
# (--inset 0); iOS applies its own squircle mask on top.
# Light: the blue artwork, full-bleed and opaque (App Store rejects alpha).
"$TOOL" ios "$IOS_SOURCE" "$IOS_SET/AppIcon-1024.png" --inset 0
# Dark (iOS 18+): the same composition on the navy ground.
"$TOOL" ios "$IOS_DARK_SOURCE" "$IOS_SET/AppIcon-1024-Dark.png" --inset 0
# Tinted (iOS 18+): grayscale; the system applies the user's tint to it. Derived
# from the navy artwork, whose darker background gives the tint more contrast to
# work with than the bright blue one does.
"$TOOL" ios "$IOS_DARK_SOURCE" "$IOS_SET/AppIcon-1024-Tinted.png" --inset 0 --grayscale

cat > "$IOS_SET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "AppIcon-1024-Dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "AppIcon-1024-Tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "==> macOS icons"
rm -f "$MAC_SET"/*.png
"$TOOL" mac "$MAC_SOURCE" "$MAC_SET"

cat > "$MAC_SET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "==> verifying"
# The iOS icon must be 1024x1024 with no alpha channel.
ios_alpha="$(sips -g hasAlpha "$IOS_SET/AppIcon-1024.png" | awk '/hasAlpha/ {print $2}')"
[[ "$ios_alpha" == "no" ]] || { echo "gen-icons: iOS icon still has an alpha channel" >&2; exit 1; }

# The macOS set must survive an icns round trip — that is what Finder/Dock consume.
ICONSET="$WORK/AirControl.iconset"
mkdir -p "$ICONSET"
cp "$MAC_SET"/icon_*.png "$ICONSET/"
iconutil -c icns -o "$WORK/AirControl.icns" "$ICONSET"
echo "    icns round trip OK ($(du -h "$WORK/AirControl.icns" | cut -f1))"

echo "==> done"
