#!/usr/bin/env bash
# scripts/check-xcstrings.sh [root-dir]
#
# Fails if any `.xcstrings` String Catalog under [root-dir] (default: repo root) has a key
# whose "en" (source language) value is missing or empty. Every user-facing string is required
# to go through a String Catalog (PR template checklist) — this catches a string that was added
# to the catalog structurally (e.g. by Xcode extracting a new `String(localized:)` call) but
# never given English source text.
#
# A `.xcstrings` file is JSON shaped like:
#   { "sourceLanguage": "en", "strings": { "<key>": { "localizations": { "en": { "stringUnit": { "value": "..." } } } } } }
# A key can also be a plain dictionary/variation entry; we walk every localizations.en.stringUnit.value
# (including inside "variations" substitutions) that exists, and separately flag keys that have no
# "en" localization at all — both count as "missing English value".
set -euo pipefail

root_dir="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (scripts/Brewfile installs it)" >&2
  exit 1
fi

# Portable (works on macOS's bash 3.2, not just bash 4+ where `mapfile` would be simpler):
# collect matches via process substitution instead of a piped subshell, so the counters below
# survive outside the loop.
count=0
fail=0

# jq program: for every string key, decide whether an English source value exists anywhere
# (top-level stringUnit, or inside any device/plural variation). Emit one line per bad key.
jq_program='
def has_en_value:
  .localizations.en as $en
  | if $en == null then false
    else
      ( ($en.stringUnit.value // "") | length > 0 )
      or
      ( ($en.variations.plural // {}) | to_entries | any(.value.stringUnit.value // "" | length > 0) )
      or
      ( ($en.variations.device // {}) | to_entries | any(.value.stringUnit.value // "" | length > 0) )
    end;

.strings
| to_entries
| map(select(.value.shouldTranslate != false))
| map(select(.value | has_en_value | not))
| .[].key
'

while IFS= read -r -d '' catalog; do
  count=$((count + 1))
  bad_keys="$(jq -r "$jq_program" "$catalog" 2>/dev/null || echo "__PARSE_ERROR__")"

  if [ "$bad_keys" = "__PARSE_ERROR__" ]; then
    echo "FAIL: $catalog — not valid JSON / unexpected shape" >&2
    fail=1
    continue
  fi

  if [ -n "$bad_keys" ]; then
    echo "FAIL: $catalog has keys with a missing/empty English value:" >&2
    while IFS= read -r key; do
      [ -n "$key" ] && echo "  - $key" >&2
    done <<< "$bad_keys"
    fail=1
  fi
done < <(find "$root_dir" \
  -type d \( -name ".build" -o -name "DerivedData" -o -name "*.xcodeproj" -o -path "*/tools/*" \) -prune -o \
  -type f -name "*.xcstrings" -print0)

if [ "$count" -eq 0 ]; then
  echo "No .xcstrings files found under $root_dir — nothing to check."
  exit 0
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "OK: $count .xcstrings file(s), all keys have an English value."
