#!/usr/bin/env bash
# scripts/release/bump-cask.sh <version-tag> <path/to/dmg.sha256>
#
# Opens a PR against the project's Homebrew tap (arch §9.4, decisions R-14: "start with
# `brew tap <owner>/airmouse`") bumping Casks/air-mouse.rb to the new version and sha256.
#
# This repo's own Formula/Casks/air-mouse.rb (owned by this repo) is the template/reference
# copy; the tap lives in a separate repository (HOMEBREW_TAP_REPO below) because `brew tap`
# expects a repo named `homebrew-<name>`. This script:
#   1. Updates the local template in place (so it never drifts from what ships).
#   2. Clones the tap repo using HOMEBREW_TAP_TOKEN, applies the same edit, and opens a PR.
#
# Required environment:
#   HOMEBREW_TAP_TOKEN   PAT (or GitHub App token) with write access to the tap repo, scoped
#                         to this repo's `release` Environment (arch §9.3).
# Optional environment:
#   HOMEBREW_TAP_REPO    defaults to "OWNER/homebrew-airmouse" — replace OWNER once the tap exists.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <version-tag> <path/to/dmg.sha256>" >&2
  exit 1
fi

version_tag="$1"
sha256_file="$2"
version="${version_tag#v}"

if [ ! -f "$sha256_file" ]; then
  echo "error: sha256 file not found: $sha256_file" >&2
  exit 1
fi

sha256="$(awk '{print $1}' "$sha256_file")"
if [ -z "$sha256" ]; then
  echo "error: could not parse sha256 from $sha256_file" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
local_cask="$repo_root/Formula/Casks/air-mouse.rb"

if [ ! -f "$local_cask" ]; then
  echo "error: local cask template not found: $local_cask" >&2
  exit 1
fi

update_cask() {
  local target="$1"
  sed -e "s/^  version \".*\"/  version \"${version}\"/" \
      -e "s/^  sha256 \".*\"/  sha256 \"${sha256}\"/" \
      "$local_cask" > "$target.tmp"
  mv "$target.tmp" "$target"
}

echo "Updating local template $local_cask (version=${version}, sha256=${sha256})"
update_cask "$local_cask"

if [ -z "${HOMEBREW_TAP_TOKEN:-}" ]; then
  echo "warning: HOMEBREW_TAP_TOKEN not set — updated the local template only, skipping tap PR" >&2
  exit 0
fi

tap_repo="${HOMEBREW_TAP_REPO:-OWNER/homebrew-airmouse}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

echo "Cloning tap $tap_repo"
git clone "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${tap_repo}.git" "$work_dir/tap"

mkdir -p "$work_dir/tap/Casks"
update_cask "$work_dir/tap/Casks/air-mouse.rb"

pushd "$work_dir/tap" >/dev/null
branch="bump-air-mouse-${version}"
git config user.name "air-mouse-release-bot"
git config user.email "release@users.noreply.github.com"
git checkout -b "$branch"
git add "Casks/air-mouse.rb"

if git diff --cached --quiet; then
  echo "No changes to the cask — already up to date."
  popd >/dev/null
  exit 0
fi

git commit -m "air-mouse ${version}"
git push -u origin "$branch"

if command -v gh >/dev/null 2>&1; then
  GH_TOKEN="$HOMEBREW_TAP_TOKEN" gh pr create \
    --repo "$tap_repo" \
    --title "air-mouse ${version}" \
    --body "Automated bump from air-mouse release.yml for ${version_tag}. sha256: \`${sha256}\`" \
    --head "$branch" \
    --base main
else
  echo "warning: gh not found — branch '${branch}' pushed to ${tap_repo}, open the PR manually" >&2
fi
popd >/dev/null
