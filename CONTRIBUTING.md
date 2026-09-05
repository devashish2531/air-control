# Contributing to Air Mouse

Thanks for considering a contribution. This document is the practical companion to
[`docs/04-architecture.md`](docs/04-architecture.md) and [`docs/05-plan.md`](docs/05-plan.md)
§8 — read those if something here is unclear about *why*, not just *how*.

## 1. Bootstrap (no `sudo` needed beyond the Xcode license)

You need a Mac with Xcode 26.6 installed (`.xcode-version` at the repo root pins the exact
version CI expects). If the Xcode license hasn't been accepted yet on your machine:

```bash
sudo xcodebuild -license accept   # one-time, if you see a license prompt
```

Everything else is `sudo`-free:

```bash
git clone https://github.com/OWNER/air-mouse.git
cd air-mouse
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # Makefile also sets this
scripts/bootstrap.sh     # brew bundle (scripts/Brewfile), fetches XcodeGen into tools/bin/,
                          # copies Config/Local.xcconfig.example -> Config/Local.xcconfig,
                          # runs `make gen`
make kit-test             # fastest loop — pure SwiftPM, no simulator/signing needed
make build                 # kit + iOS (simulator, unsigned) + Mac (unsigned)
```

Edit `Config/Local.xcconfig` (git-ignored) with your own `DEVELOPMENT_TEAM` (a free personal
Apple Developer team works) and a `BUNDLE_ID_SUFFIX` like `.dev-yourname` — this keeps your
debug helper's bundle ID distinct from anyone else's and from a future release install, which
matters for TCC and Launch Services (see §5 below).

The project path may contain spaces (e.g. `~/Desktop/Projects/Air Mouse`) — always quote paths
in shell commands. `make` targets already do this for you.

## 2. Architecture map (summary — see `docs/04-architecture.md` for the full picture)

```
Packages/AirMouseKit/   AirMouseProtocol (pure data, Foundation only)
                        → AirMouseCrypto, AirMouseFilters (independent of each other)
                        → AirMouseCore (session logic, no Network.framework)
                        → airmouse-cli (the only kit target that imports Network)
apps/AirMouse-iOS/      SwiftUI app; Sources/{App,Features,Services,Support}
apps/AirMouse-Mac/      Menu-bar helper; Sources/{App,Features,Services,Support}
Config/                 Base.xcconfig (committed) + Local.xcconfig (git-ignored, per-dev)
```

Layering rules: `AirMouseProtocol` never imports anything but Foundation.
`AirMouseCore` never imports `Network`. Only `airmouse-cli` and the two apps do. If you need a
type owned by a module you're not working in and it doesn't exist yet, write a minimal
`protocol` in your own module rather than reaching into someone else's in-flight work, and say
so in your PR description.

## 3. How to add a new message type

Message types are the interface between the iOS app and the Mac helper (`docs/03-specifications.md`
§3.4.5, `docs/protocol.md`). To add one:

1. Add the payload struct and a case to `Message` in `AirMouseProtocol/Messages/` (kit). Give
   it a `t` string in the message catalogue's camelCase convention and list required/optional
   fields explicitly — unknown fields must decode as ignored, missing required fields must
   fail decode (spec §3.4.2).
2. Add round-trip + golden-vector tests in `AirMouseProtocolTests` (a new message needs at
   least an encode→decode test; see `scripts/gen-vectors.swift` if it needs a checked-in
   vector).
3. If it's additive (new type, new optional field, new enum value), it does **not** bump the
   protocol major version (spec §3.7) — but you do need a `docs/protocol.md` CHANGELOG entry
   and, if a capability gates it, add the capability string to `hello`/`helloAck`
   (`AirMouseCore`) on both sides.
4. Wire it up on whichever side(s) send/receive it — never touch the transport layer
   (`AirMouseCore/Transport`) itself just to add a message; it only carries frames.
5. If the Mac needs to react to it, add/extend a case in the loopback integration harness
   (`apps/AirMouse-Mac/IntegrationTests`) so `RecordingInjector` can assert the resulting
   `CGEvent`-equivalent without a real phone.

## 4. How to add a new macro action kind

Macros are host-authored only in v1 — the phone is a read-only consumer (decisions Addendum
A9). To add an action kind:

1. Add the case to `MacroAction` in `AirMouseMacroModel` / `AirMouseProtocol/Macros` and to
   `MacroValidator` (limits: 64 macros per host, 1 concurrent script process, 30–60 s timeout
   — spec §7.6).
2. Implement execution in `apps/AirMouse-Mac/Sources/Services/MacroEngine/ScriptRunner` (or the
   relevant non-script executor). Script-capable actions **must** stay gated behind the global
   *and* per-device opt-in and require on-phone confirmation before running (spec §5.5.5, §7.2)
   — never add a path that bypasses either gate.
3. Extend `apps/AirMouse-Mac/Sources/Features/MacroEditor` so a host can author the new kind.
4. Add fixtures to the loopback harness's `macroList` so the iOS side can be tested against the
   new kind without a Mac UI (plan §5 notes this is exactly how M7 was designed to parallelize).
5. Never let a macro action touch the transport layer directly — it goes through the same
   `EventInjector`/`MacroEngine` path as everything else, so rate limits and stale-session
   release-all logic (spec §5.3.11) still apply to it.

## 5. TCC troubleshooting

If Accessibility permission seems to silently reset after a rebuild, it's almost always one of:

- **Ad-hoc/ephemeral signing.** Debug builds must use a *stable* Apple Development identity via
  `Config/Local.xcconfig` (decisions Addendum A10) — ad-hoc signing gets a new identity every
  build, and TCC keys its Accessibility grant on the signing identity + bundle ID.
- **A stale grant for an old `BUNDLE_ID_SUFFIX`.** If you changed your `BUNDLE_ID_SUFFIX`,
  the old bundle ID's grant is orphaned, not reused.

Reset and re-grant:

```bash
tccutil reset Accessibility com.airmouse.helper.dev-<yourname>
```

Then relaunch the helper and accept the Accessibility prompt again (or add it manually at
System Settings › Privacy & Security › Accessibility).

## 6. Stable dev signing identity

`Config/Base.xcconfig` includes `Config/Local.xcconfig` (git-ignored) via `#include? "Local.xcconfig"`.
Set at minimum:

```
DEVELOPMENT_TEAM = ABCDE12345      # your Apple Development team (a free personal team works)
BUNDLE_ID_SUFFIX = .dev-yourname   # keeps your build's TCC/Launch Services identity distinct
```

`scripts/bootstrap.sh` copies `Config/Local.xcconfig.example` to `Config/Local.xcconfig` for you
on first run if it doesn't already exist — you still need to fill in your own team ID.

## 7. PR checklist

The pull request template (`.github/PULL_REQUEST_TEMPLATE.md`) has the full checklist; in short:

- Cite the spec/arch section(s) you read and implemented against.
- Tests added/updated at the right level (kit `swift test`, app `Mock*` view-model tests, or
  Mac loopback integration test — see `docs/04-architecture.md` §10).
- Builds clean under Swift 6 strict concurrency; no new third-party dependencies without prior
  discussion; new user-facing strings go in a String Catalog, checked by
  `scripts/check-xcstrings.sh`.
- Protocol changes get a `docs/protocol.md` CHANGELOG entry; UI changes get light+dark
  screenshots.
- Changes under `Packages/AirMouseKit/Sources/AirMouseCrypto`, `docs/protocol.md`, or
  `.github/workflows/` need a CODEOWNERS review (see `.github/CODEOWNERS`).

## 8. Commit style

Short, imperative subject line; reference the milestone/task ID from `docs/05-plan.md` when
one exists (e.g. `M4-06: add ScrollGain table + tests`). Squash merge is used on `main`, so
intermediate "fixup" commits within a PR are fine — write the PR description as the summary
that will actually ship in the merge commit.
