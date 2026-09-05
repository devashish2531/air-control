# Air Mouse

[![CI](https://github.com/OWNER/air-mouse/actions/workflows/ci.yml/badge.svg)](https://github.com/OWNER/air-mouse/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Turn your iPhone or iPad into a wireless mouse, trackpad, and keyboard for your Mac — pointer,
scroll, typing, media keys, and presenter/remote controls, all over your local Wi-Fi network.
No cloud, no account, no telemetry.

> **A note on the name.** "Air Mouse" is currently a working name chosen during development.
> It collides with existing App Store listings, so a trademark/App Store name search will
> happen before this project goes public and the name may change (see
> [`docs/00-decisions.md`](docs/00-decisions.md) Addendum A8). Bundle identifiers
> (`com.airmouse.*`) will follow whatever name is finally chosen.

## Features

- **Touchpad mode** — relative pointer movement, click, drag, scroll with momentum, pinch/zoom.
- **Air-mouse mode** — point with your phone's gyroscope, like a laser pointer for your cursor.
- **Keyboard mode** — full keyboard passthrough, including modifier chords and media keys.
- **Presenter/remote** — slide navigation and host-authored macros (keystroke sequences,
  app launches, and opt-in scripts) triggered from your phone.
- **Secure by construction** — mutual TLS 1.3 with certificate pinning from a QR code, and
  authenticated encryption on every motion packet. See [Security model](#security-model).
- **No telemetry** — nothing is collected automatically; the in-app Latency HUD and
  Diagnostics export are for *you*, not us.

## Screenshots

_Coming soon — the app is still in early development (see [Project status](#project-status))._

## Install

### Mac (the "helper")

**Homebrew cask (recommended once a release exists):**

```bash
brew tap OWNER/airmouse
brew install --cask air-mouse
```

**Direct download:** grab the latest notarized `.dmg` from
[GitHub Releases](https://github.com/OWNER/air-mouse/releases), open it, and drag
`AirMouseHelper.app` to Applications.

**Build from source:** see [`CONTRIBUTING.md`](CONTRIBUTING.md) for the bootstrap runbook —
`scripts/bootstrap.sh && make mac-build`.

### iOS / iPadOS

TestFlight / App Store distribution: **TBD** — not yet published. Until then, build from
source: `scripts/bootstrap.sh && make ios-build` (see
[`CONTRIBUTING.md`](CONTRIBUTING.md)), or run `make ios-test` to exercise it in the simulator
without a phone at all.

## Quick start (pairing)

1. Launch **AirMouseHelper** on your Mac — it lives in the menu bar. Click the menu bar icon
   and choose **Pair a Device** to open the Pairing window; it shows a QR code that refreshes
   every 60 seconds.
2. Open **Air Mouse** on your iPhone/iPad and scan the QR code (or paste the pairing link if
   you can't scan — Settings shows a "paste pairing link" field).
3. Your phone and Mac perform a mutual-TLS handshake bound to a one-time secret from the QR
   code; once it succeeds, your Mac is added to Trusted Devices and you land straight on the
   Touchpad screen.
4. On your Mac, grant **Accessibility** access when prompted (System Settings › Privacy &
   Security › Accessibility) — this is the only permission Air Mouse ever asks for.
5. Reconnecting later is automatic: open the app while your Mac is on the same network and it
   finds and reconnects to a trusted host without scanning anything again.

## Security model

- **Mutual TLS 1.3**, self-signed P-256 identities on both sides, pinned by SHA-256
  certificate fingerprint exchanged in the pairing QR code — no certificate authority, no
  "trust any device" mode.
- **Authenticated encryption on every motion packet** (ChaCha20-Poly1305, per-session keys
  derived via HKDF, a sliding replay window) so a passive or active LAN attacker can neither
  read nor inject pointer/keyboard input.
- **One permission only: Accessibility.** Air Mouse never requests Input Monitoring or Screen
  Recording, and posts input the same way any accessibility tool does — there are no raw
  event taps.
- **Macros are host-authored and opt-in.** Your phone is a read-only consumer of macros your
  Mac defines; any macro that runs a script requires both a global and a per-device opt-in
  plus an on-phone confirmation before it executes.
- **No telemetry, no third-party SDKs.** The only outside dependency on the Mac side is
  Sparkle, used solely for signed update checks — there is no analytics of any kind.

See [`docs/00-decisions.md`](docs/00-decisions.md) §Addendum A and
[`docs/03-specifications.md`](docs/03-specifications.md) §7 for the full threat model, and
[`SECURITY.md`](SECURITY.md) to report a vulnerability.

## Architecture

The system design — module boundaries, threading model, the wire protocol, and every
architecture decision record — lives in [`docs/`](docs/):

- [`docs/00-decisions.md`](docs/00-decisions.md) — fixed decisions and addenda (read this first;
  it overrides everything else if they disagree).
- [`docs/04-architecture.md`](docs/04-architecture.md) — repository layout, module diagrams,
  concurrency model, build/CI/release architecture, testing architecture.
- [`docs/03-specifications.md`](docs/03-specifications.md) — the full wire protocol, state
  machines, and security specification.
- [`docs/protocol.md`](docs/protocol.md) — a shorter, contributor-facing extraction of just the
  wire protocol, for anyone implementing a client or host without reading the whole spec.
- [`docs/05-plan.md`](docs/05-plan.md) — the milestone roadmap and delivery plan.

## Project status

Air Mouse is under active early development; there is no public release yet. Follow
[`docs/05-plan.md`](docs/05-plan.md) for the milestone roadmap, or the
[good first issues](docs/ISSUES-initial.md) for ways to help.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the local setup (no `sudo` required beyond
accepting the Xcode license once), how to add a new message type or macro action kind, and
the PR checklist. Please also read the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE).
