# Air Mouse — Stakeholder Decisions (captured 2026-09-03)

These answers were given by the project owner during the requirements interview and are the
authoritative constraints for all downstream documents (requirements, specifications, architecture, plan).

## Product shape
- **Platforms:** iPhone and iPad client controlling a macOS host.
- **Input modes (all in scope for v1):**
  1. Touchpad surface — phone screen acts as a trackpad (drag to move, tap to click, two-finger scroll, gestures).
  2. Motion / gyro "air mouse" — point the device in the air; gyroscope + accelerometer drive the cursor; requires drift correction.
  3. Keyboard input — send text, keystrokes, shortcuts, media keys.
  4. Presenter / media remote — slide next/prev, volume, play/pause, app launcher buttons.
- **Extras in v1 scope:**
  - iPad-optimized layout (split trackpad + keyboard, landscape, external keyboard passthrough).
  - Custom macro / shortcut buttons (user-defined, fire key combos or launch apps, synced from Mac).
- **Explicitly out of v1 scope:** Multi-Mac switching, Apple Watch companion. (May be listed as future work.)

## Transport & security
- **Transport:** Companion Mac menu-bar helper app over local Wi-Fi. Bonjour discovery.
- **Pairing:** QR code pairing + TLS. Mac shows QR (address + one-time secret); phone scans; keys derived; certificates pinned; trusted devices remembered.
- **Bluetooth HID:** Not feasible on iOS (apps cannot act as BLE HID peripheral) — excluded.

## Distribution & stack
- **Goal:** Open source project (public GitHub repo, permissive license, contributor docs, CI).
- **Stack:** Native Swift/SwiftUI on both sides. Mac helper uses CGEvent for injection. Shared Swift package for protocol.
- **Minimum OS:** iOS 18 / iPadOS 18 / macOS 15 Sequoia.

## Performance
- **Target:** Trackpad-grade feel, < 20 ms end-to-end motion latency.
- Implies: UDP (or unreliable datagram) for motion events, 120 Hz sampling on ProMotion devices, prediction/smoothing, TCP/reliable channel for control messages.

---

## Addendum A — Decisions derived from research (2026-09-03, pending owner confirmation)

These resolve items left open in `01-requirements.md`, using findings in `02-technical-research.md`.
They are marked *provisional*; the owner may override them.

| # | Topic | Decision | Rationale |
|---|-------|----------|-----------|
| A1 | Control channel | **TCP + mutual TLS 1.3**, self-signed P-256 identities on both sides, pinned by SHA-256 fingerprint exchanged via the QR code. | TLS-PSK is TLS 1.2-only on Apple platforms (verified). Cert pinning is the supported path. |
| A2 | Motion channel | **Plain UDP with application-layer ChaChaPoly (CryptoKit)**: per-session key delivered over the TLS channel, 64-bit counter nonce, sliding replay window. Falls back to the TCP channel when UDP is blocked. | DTLS in Network.framework is undocumented/1.2-ish; app-layer AEAD is simpler, auditable, and avoids handshake state on the lossy path. |
| A3 | QUIC | **Deferred to v2 spike.** Not used in v1. | Datagram support exists (iOS 15+) but adds risk; two-socket design is well understood. |
| A4 | Networking API | `NWConnection` / `NWListener` / `NWBrowser` (callback APIs). Do **not** use the Swift-concurrency `NetworkConnection` family (iOS 26 / macOS 26 only). | OS floor is iOS 18 / macOS 15. |
| A5 | macOS permissions | Request **Accessibility only**. Never request Input Monitoring (no event taps) or Screen Recording. | Posting events needs only the Accessibility/PostEvent TCC bucket (verified). |
| A6 | Mac distribution | Direct: Developer ID + Hardened Runtime + notarization, GitHub Releases + Homebrew cask, Sparkle (EdDSA-signed) for updates. Not sandboxed. | Sandbox/CGEvent interaction is uncertain and unnecessary for direct distribution. |
| A7 | License | **MIT** (recommended default). | Maximizes contributor uptake; no patent clauses needed for this project. |
| A8 | Project name | Keep **"Air Mouse" as the codename**; do a trademark/App Store name search before the repo goes public. Candidates: Waft, Glidepad, Hover Remote. | Name collides with existing App Store apps. |
| A9 | Macros | Host-authored only in v1; phone is read-only consumer. AppleScript/shell actions gated behind global + per-device opt-in and on-phone confirmation. | Security lessons from Remote Mouse / Unified Remote CVEs. |
| A10 | Debug signing | Debug builds signed with a stable Apple Development identity via git-ignored `Local.xcconfig`. | Ad-hoc signing resets TCC Accessibility grant on every rebuild. |

## Addendum B — Spec decisions that reinterpret the PRD (2026-09-03, pending owner confirmation)

Raised by the specification author in `03-specifications.md`; defaults stand unless the owner objects.

| # | Topic | Spec decision | PRD said |
|---|-------|---------------|----------|
| B1 | Scroll momentum | Client decides (fling velocity, cancel-on-touch); Mac runs the 60 Hz decay so momentum survives packet loss. | Client generates momentum (FR-TP-013). |
| B2 | `_airmouse._udp` Bonjour record | Registered for FR-DP-001 compliance but never browsed; UDP port comes from TXT/QR. | Implied both would be browsed. |
| B3 | Manual pairing fallback | Full `airmouse://pair?...` URL is the only manual fallback; no short numeric code, to preserve the 128-bit secret. | Left open. |
| B4 | Motion payload | 16-byte payload: flags, source, samples, reserved, ts µs, dx/dy/scrollX/scrollY as i16 in 1/8 pt; sequence lives in the AEAD counter. | 32-bit sequence field (FR-CR-002) — satisfied by counter low 32 bits. |
| B5 | Prediction | Off by default on both sides (Labs toggle). | Not specified. |
| B6 | Default port | 47800 for TCP and UDP, ephemeral fallback advertised in TXT/QR. | Not specified. |

## Addendum C — Architecture reconciliations (2026-09-04)

| # | Topic | Decision |
|---|-------|----------|
| C1 | Shared package naming | `AirMouseKit` with targets `AirMouseProtocol`, `AirMouseCrypto`, `AirMouseFilters`, `AirMouseCore`, plus `airmouse-cli`. Supersedes spec §2.1/§2.4 names (`AirMouseWire`/`InputCore`/`MacroModel`). See `04-architecture.md` ADR-001. |
| C2 | Project generation | XcodeGen `project.yml` per app; generated `.xcodeproj` files are git-ignored. |
| C3 | Dev machine fact | Xcode 26.6 (17F113) **is installed** but its license is unaccepted and `xcode-select` points at Command Line Tools. M0 begins with `sudo xcode-select -s /Applications/Xcode.app` and `sudo xcodebuild -license accept`, not an Xcode install. |
