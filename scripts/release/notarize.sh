#!/usr/bin/env bash
# scripts/release/notarize.sh <path/to/AppName.app>
#
# Zips the exported, Developer-ID-signed app, submits it to Apple notarization via
# `xcrun notarytool`, waits for a result, and staples the ticket back onto the .app.
#
# Required environment (arch §9.3 — only present in the `release` GitHub Environment):
#   ASC_KEY_ID       App Store Connect API key ID
#   ASC_ISSUER_ID    App Store Connect API issuer ID
#   ASC_KEY_P8       base64-encoded contents of the .p8 private key file
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <path/to/AppName.app>" >&2
  exit 1
fi

app_path="$1"

if [ ! -d "$app_path" ]; then
  echo "error: not a directory: $app_path" >&2
  exit 1
fi

for var in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8; do
  if [ -z "${!var:-}" ]; then
    echo "error: required environment variable $var is not set" >&2
    exit 1
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

key_path="$work_dir/AuthKey_${ASC_KEY_ID}.p8"
echo "$ASC_KEY_P8" | base64 --decode > "$key_path"
chmod 600 "$key_path"

app_name="$(basename "$app_path")"
zip_path="$work_dir/${app_name%.app}.zip"

echo "Zipping $app_path -> $zip_path"
ditto -c -k --keepParent "$app_path" "$zip_path"

echo "Submitting to notarytool (this can take a few minutes)..."
xcrun notarytool submit "$zip_path" \
  --key "$key_path" \
  --key-id "$ASC_KEY_ID" \
  --issuer "$ASC_ISSUER_ID" \
  --wait

echo "Stapling ticket to $app_path"
xcrun stapler staple "$app_path"

echo "Validating staple"
xcrun stapler validate "$app_path"

echo "Notarization complete for $app_path"
