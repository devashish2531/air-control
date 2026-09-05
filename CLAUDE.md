# Air Mouse — agent & contributor guide

Open-source iPhone/iPad app that controls a Mac over local Wi-Fi via a Swift menu-bar helper.
Native Swift 6 / SwiftUI on both sides. iOS 18+ / macOS 15+. Strict concurrency is ON.

## Read before coding
The design is fully specified. Read the relevant section BEFORE writing code, and cite it in code comments (`// spec §3.5.2`).
- `docs/00-decisions.md` — fixed decisions + addenda. Never contradict.
- `docs/03-specifications.md` — wire protocol, byte layouts, state machines, constants (§11.3 has every constant).
- `docs/04-architecture.md` — module boundaries, threading, ADRs. §3 maps every type to a directory.
- `docs/01-requirements.md`, `docs/02-technical-research.md` — background; consult when the spec is silent.

## Layout
```
Packages/AirMouseKit/            SwiftPM kit: AirMouseProtocol (pure data) → AirMouseCrypto, AirMouseFilters → AirMouseCore → airmouse-cli
apps/AirMouse-iOS/               XcodeGen project.yml → AirMouse.xcodeproj (git-ignored). Sources/{App,Features,Services,Support}
apps/AirMouse-Mac/               XcodeGen project.yml → AirMouseHelper.xcodeproj (git-ignored). Sources/{App,Features,Services,Support}
Config/                          Base.xcconfig (+ git-ignored Local.xcconfig for DEVELOPMENT_TEAM)
```
Layering rules (arch §3.1): `AirMouseProtocol` imports Foundation only. `AirMouseCore` never imports Network. Apps depend on Core.
Only `airmouse-cli` and the two apps import Network.framework.

## Build & test (no sudo, no xcode-select needed)
```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # Makefile sets this for you
make kit-test        # fastest loop — run after every kit change
make ios-build       # simulator build, unsigned
make mac-build       # macOS build, unsigned
make build           # all three
make gen             # regenerate .xcodeproj after adding/removing files or editing project.yml
```
XcodeGen lives at `tools/bin/xcodegen` (git-ignored; `scripts/bootstrap.sh` fetches it). There are no code-signing identities on this machine;
builds run with `CODE_SIGNING_ALLOWED=NO`. Never commit `*.xcodeproj`.
The project path contains a space — always quote paths in shell.

## Conventions
- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete`. Prefer actors and `Sendable` value types. `@MainActor` only for UI.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Put golden vectors in `Tests/*/Vectors/*.json`.
- One type per file; file name == type name. Directory per module as listed in arch §3.
- No third-party dependencies beyond `swift-certificates`, `swift-argument-parser`, and (Mac, later) Sparkle.
- Logging via `os.Logger` with subsystem `com.airmouse.<app>`; never log keys, secrets, text typed, or full fingerprints (spec §7).
- Every wire constant comes from `AirMouseProtocol` constants, never literals in apps.
- Multiple agents work in parallel in this repo. Only touch files inside the directories you were assigned. If you need a type
  owned by another module that does not exist yet, write a minimal `protocol` in your own module and note it in your report.
- Do not run `git commit` unless asked. Do not edit `docs/0*.md`; write deviations to your final report instead.

## Hard safety rules (added 2026-09-05 after an incident)
- NEVER delete, reset, or modify keychain items, certificates, identities, or private keys that this project did not create. The only keychain items agents may touch are those with this project's own labels/services (`com.airmouse.*`), and even those only via the app's own `IdentityStore`/`KeychainStore` code paths or an explicitly scoped `security delete-generic-password -s com.airmouse.*`. No `security delete-certificate`, `delete-identity`, `delete-keychain`, or keychain-wide loops, ever.
- No destructive system changes outside the repo (TCC resets other than `tccutil reset Accessibility com.airmouse.helper*`, launchd, network settings, other apps' data) without the owner's explicit, per-action approval.
- When a task seems to require anything above, stop and report instead.
