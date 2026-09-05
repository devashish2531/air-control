# Air Mouse cask — project tap (decisions R-14: "start with `brew tap <owner>/airmouse`",
# then submit to homebrew-cask once the project is notable enough, per Homebrew policy).
#
# This file is the template that scripts/release/bump-cask.sh edits in place on every
# release and mirrors into the separate tap repository. `version`/`sha256` below are
# placeholders until the first tagged release runs.
#
# PLACEHOLDERS a maintainer must fill in before first use:
#   OWNER          — GitHub org/user (appears in `url`, `homepage`)
#   version/sha256 — set automatically by scripts/release/bump-cask.sh after v0.1.0 ships
cask "air-mouse" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/OWNER/air-mouse/releases/download/v#{version}/AirMouse-#{version}.dmg"
  name "Air Mouse"
  desc "Control your Mac's pointer, keyboard, and media keys from your iPhone/iPad over local Wi-Fi"
  homepage "https://github.com/OWNER/air-mouse"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia" # macOS 15+ (arch: iOS 18+ / macOS 15+ floor)

  app "AirMouseHelper.app"

  # Notes for the tap: this cask is Developer ID + notarized + Hardened Runtime, not
  # sandboxed (decisions Addendum A6). It requests Accessibility only — never Input
  # Monitoring or Screen Recording (Addendum A5).
  postflight do
    # Nothing to run post-install today; AirMouseHelper is a menu-bar app the user
    # launches themselves. Placeholder kept for a future login-item registration step.
  end

  zap trash: [
    "~/Library/Application Support/AirMouseHelper",
    "~/Library/Preferences/com.airmouse.helper.plist",
    "~/Library/Caches/com.airmouse.helper",
    "~/Library/Saved Application State/com.airmouse.helper.savedState",
    "~/Library/HTTPStorages/com.airmouse.helper",
  ]

  caveats <<~EOS
    Air Mouse requests **Accessibility** permission only, to post pointer/keyboard events
    to the system (spec §7.5). macOS prompts for this on first launch; you can also grant
    it manually at System Settings › Privacy & Security › Accessibility. It never requests
    Input Monitoring or Screen Recording — if anything claiming to be Air Mouse asks you
    for those, do not grant them.

    If the Accessibility grant appears to be lost after an upgrade (uncommon for a
    Developer ID build with a stable signing identity), reset and re-grant it:
      tccutil reset Accessibility com.airmouse.helper

    "Air Mouse" is currently a working name (see docs/00-decisions.md Addendum A8) and may
    be renamed before a stable App Store / production release; bundle identifiers and this
    cask's token will be updated accordingly if that happens.
  EOS
end
