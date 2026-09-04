# Air Mouse — Product Requirements Document (v1)

| Field | Value |
|---|---|
| Document | 01-requirements.md |
| Status | Draft for owner review |
| Date | 2026-09-03 |
| Upstream | `docs/00-decisions.md` (authoritative; nothing here overrides it) |
| Downstream | 02-specifications (protocol, gesture spec), 03-architecture, 04-plan |
| Audience | Contributors, reviewers, designers, the project owner |

Anything in this document that is not settled in `00-decisions.md` is a recommendation and is tagged **(recommended default)**. Those items need the owner's explicit confirmation or rejection before the specification phase.

---

## 1. Vision & goals

Air Mouse turns the iPhone or iPad you already carry into a trackpad-grade pointer, an in-the-air remote, a keyboard, and a programmable button deck for a Mac — with nothing but the local Wi-Fi network between them. Existing remote-control apps feel laggy, treat security as an afterthought, hide the good features behind subscriptions, or route your keystrokes through someone's cloud. Air Mouse is the opposite on every axis: sub-20 ms motion latency that is indistinguishable from a physical trackpad, a cryptographic pairing model where every byte is encrypted end to end on your own network, zero accounts, zero telemetry by default, and a fully open-source codebase (native Swift/SwiftUI on both platforms, shared protocol package) that anyone can audit, build, and extend. The Mac side is a quiet menu-bar helper; the phone side is an app you can hand to a guest on the couch without explaining anything.

### 1.1 Goals for v1

1. Ship a complete, polished input suite: touchpad, gyro air-mouse, keyboard, presenter/media remote, custom macro buttons, iPad-optimized layout.
2. Make the first-run experience so short that "install, pair, move the cursor" is a single sitting with no manual.
3. Establish a secure-by-default local protocol that the community can trust and reuse.
4. Publish a contributor-friendly open-source project (permissive license, docs, CI, reproducible builds).

### 1.2 Success metrics

Telemetry is off by default (see NFR-SEC-010), so the metrics below are measured via (a) the built-in local diagnostics screen, (b) opt-in beta (TestFlight) diagnostics, and (c) scripted lab tests documented in the repo. GitHub stars, downloads, and social mentions are explicitly **not** success metrics.

| # | Metric | Target | How measured |
|---|---|---|---|
| M1 | Time to first cursor move (TTFCM): from tapping "Get" on the iOS App Store to the first cursor movement on the Mac, including installing the Mac helper and granting Accessibility | Median ≤ 90 s, p90 ≤ 3 min | Moderated usability sessions (n ≥ 10) before launch; opt-in beta funnel timestamps |
| M2 | End-to-end motion latency (finger/IMU sample → `CGEvent` posted on Mac) | p50 ≤ 12 ms, p95 ≤ 20 ms, p99 ≤ 30 ms on 5 GHz Wi-Fi | In-app "Latency test" using clock-synced round-trip probe; lab harness with high-speed camera as ground truth |
| M3 | Crash-free sessions (both apps) | ≥ 99.5 % | Opt-in crash reports (beta) + Xcode Organizer for App Store build |
| M4 | Auto-reconnect success after a Wi-Fi interruption shorter than 10 s | ≥ 99 % recover without user action, within 3 s of network return | Lab test (scripted AP toggling) + beta diagnostics |
| M5 | Pairing success on first attempt | ≥ 95 % | Usability sessions + beta funnel |
| M6 | Battery drain on iPhone while actively connected | ≤ 8 %/h touchpad mode, ≤ 12 %/h gyro mode (iPhone 15-class, 50 % brightness) | Lab test, 60-minute scripted session |

---

## 2. Target users & personas

| Persona | Primary mode | Device | Network reality |
|---|---|---|---|
| Couch / HTPC user | Touchpad + media remote | iPhone | Consumer router, often 2.4 GHz, sometimes mesh |
| Presenter | Gyro air-mouse + presenter buttons | iPhone | Hostile: conference Wi-Fi with client isolation, or a hotspot |
| Headless Mac mini developer | Keyboard + touchpad + macros | iPhone or iPad | Home/office LAN, Mac has no display or keyboard attached |
| Accessibility user | Touchpad (large surface) + macros | iPad | Home LAN, needs stability above all |
| Tinkerer / contributor | Everything | Both | Wants to fork, read the protocol, add a macro type |

### 2.1 Priya — the couch / HTPC user
- **Context:** A Mac mini drives the living-room TV. She watches YouTube, Plex, and browses from the sofa; the Magic Trackpad is always dead or lost between cushions.
- **Pain:** Bluetooth keyboards are ugly on the coffee table; existing phone apps stutter, show ads, and take several taps to reconnect every evening.
- **Needs:** Open the app and be connected in under two seconds. Precise enough to hit small web-page buttons across the room. Volume, play/pause, and a "back to Plex" button within thumb reach. Works when the phone screen is dim.

### 2.2 Marcus — the presenter
- **Context:** Sales engineer presenting Keynote and live demos from a MacBook Pro in client meeting rooms, often walking around.
- **Pain:** Clickers only do next/previous; when he needs to point at a chart or open a browser tab he has to walk back to the laptop. Conference Wi-Fi often isolates clients, so he tethers everything to his phone.
- **Needs:** Gyro pointing that does not drift over a 45-minute talk; a clutch so the cursor stays still when he gestures; big next/previous/blank buttons he can find without looking; the app must work over a personal hotspot; a "start presentation" macro.

### 2.3 Dana — the headless Mac mini developer
- **Context:** Runs a Mac mini as a build server and home lab with no display or keyboard attached. Uses Screen Sharing from her laptop, but sometimes just needs to type a password, restart a service, or click "Allow" on a dialog.
- **Pain:** Pulling out the laptop for a ten-second interaction. Screen Sharing is heavy and needs a display resolution dance.
- **Needs:** Reliable keyboard passthrough including modifiers and function keys; a fast connect from the lock screen of the iPhone; macro buttons that launch Terminal, run a Shortcut, or send `⌘⇧.`; the helper must launch at login and survive reboots unattended.

### 2.4 Tomás — the accessibility user
- **Context:** Has limited fine-motor control; a phone or iPad flat on a table is easier to use than a mouse that has to be gripped.
- **Pain:** Small tap targets, accidental right-clicks, needing to hold the finger steady to drag. Apps that ignore VoiceOver and Dynamic Type.
- **Needs:** A very large touchpad surface (iPad), drag-lock, adjustable tap timing, ability to disable gestures he does not use, high-contrast big macro buttons, VoiceOver labels everywhere, haptics that can be turned off.

### 2.5 Ines — the tinkerer / contributor
- **Context:** iOS developer who wants a remote that does exactly what she wants, and is willing to contribute.
- **Pain:** Closed apps cannot be trusted with keystrokes; nobody documents their wire protocol.
- **Needs:** A readable protocol spec, a shared Swift package she can compile in minutes, CI that runs on a fork, and a `CONTRIBUTING.md` that explains how to add a macro action type without touching the transport.

---

## 3. User stories by epic

Format: `ID — As a <persona>, I want <capability> so that <outcome>.` Each has at least one acceptance criterion in Given/When/Then form. Priority: **P0** = must ship in v1, **P1** = should ship in v1, **P2** = ship if time permits (still v1 scope per decisions).

### Epic DP — Discovery & pairing (Bonjour, QR, TLS)

**AM-DP-01 (P0)** — As any user, I want the app to list Macs running the helper on my network so that I never type an IP address.
- Given the helper is running on a Mac on the same network, When I open the app's "Connect" screen, Then the Mac appears by its computer name within 2 s, with a "paired / not paired" badge.
- Given no helper is found within 5 s, When I am on the Connect screen, Then I see guidance (is the helper running? same Wi-Fi? local network permission granted?) and a "Scan QR" button.

**AM-DP-02 (P0)** — As a new user, I want to pair by scanning a QR code on the Mac so that pairing is one physical step and no secret is typed.
- Given I click "Pair new device" in the menu-bar helper, When the QR is displayed, Then it encodes the helper's address(es), port, TLS certificate fingerprint, and a one-time secret valid for 60 s, and shows a countdown.
- Given I scan that QR within its validity, When the phone connects, Then the phone verifies the certificate fingerprint, proves possession of the secret, exchanges its own client certificate, and both sides store each other as trusted; the Mac shows a "Paired with <device name>" confirmation and the phone lands on the touchpad screen within 3 s.

**AM-DP-03 (P0)** — As a security-conscious user, I want a one-time secret to be unusable twice so that a photographed QR cannot be reused.
- Given a secret has been consumed or has expired, When any device presents it, Then the helper rejects it and shows nothing sensitive in the error.

**AM-DP-04 (P0)** — As a returning user, I want a paired Mac to connect automatically so that daily use has zero pairing steps.
- Given a trusted Mac is discovered, When I open the app, Then it connects with mutual certificate verification without prompting, in ≤ 2 s from foregrounding on a warm network.

**AM-DP-05 (P1)** — As a user whose phone cannot see Bonjour (client isolation), I want to connect by scanning the QR even if discovery fails so that presenting on hostile Wi-Fi still works.
- Given Bonjour returns nothing, When I scan a QR that includes the Mac's IP/port, Then the app attempts a direct connection to the encoded addresses in order (hotspot address first when the phone is the hotspot).

**AM-DP-06 (P1)** — As a user, I want to see and remove trusted Macs on the phone so that I control what my phone can connect to.
- Given I have trusted Macs, When I open Settings › Macs, Then I see each Mac's name, last connected time, and a "Forget" action that deletes the stored certificate and key material.

**AM-DP-07 (P0)** — As a user, I want any connection attempt from an unknown or revoked device to be refused so that only devices I paired can control my Mac.
- Given a device presents a certificate not in the trusted list, When it attempts a TLS handshake, Then the helper refuses and, rate-limited, logs a local event (no network call).

### Epic TP — Touchpad mode

**AM-TP-01 (P0)** — As Priya, I want one-finger drag to move the cursor so that the phone feels like a trackpad.
- Given I am connected, When I slide one finger, Then the cursor moves with p95 latency ≤ 20 ms and no visible stepping at slow speeds.

**AM-TP-02 (P0)** — As Priya, I want tap to left-click and two-finger tap to right-click.
- Given I tap with one finger for < 200 ms with movement < 8 pt, When I lift, Then a left click is delivered; a two-finger tap delivers a secondary click.

**AM-TP-03 (P0)** — As Priya, I want double-tap to double-click, with the timing configurable.
- Given two taps arrive within the configured double-click interval (default 300 ms), Then macOS receives a click with clickState = 2 so that word selection and file opening work.

**AM-TP-04 (P0)** — As Tomás, I want tap-and-drag and drag-lock so that dragging does not require holding the finger down steadily.
- Given tap-and-drag is enabled, When I tap and then within 300 ms touch again and move, Then the mouse button is held while I move; releasing ends the drag unless drag-lock is on, in which case a subsequent tap ends it.

**AM-TP-05 (P0)** — As Priya, I want two-finger drag to scroll with momentum, in natural or inverted direction.
- Given two fingers move, Then scroll events with pixel precision are sent in the configured direction; When I fling and lift, Then scrolling decays with a momentum curve matching macOS feel and stops on the next touch.

**AM-TP-06 (P1)** — As Priya, I want pinch to zoom in web pages and photos.
- Given two fingers pinch beyond a 40 pt threshold, Then a zoom action is delivered to the frontmost app (see FR-TP-018 for the mapping and its limits).

**AM-TP-07 (P1)** — As a power user, I want three-finger swipes for Mission Control, App Exposé, and switching Spaces.
- Given three fingers swipe up/down/left/right ≥ 60 pt, Then the corresponding macOS system shortcut is sent, once per gesture.

**AM-TP-08 (P1)** — As Tomás, I want an optional three-finger drag (mutually exclusive with three-finger swipes) so that window dragging is a single gesture.
- Given three-finger drag is enabled in Settings, When I move three fingers, Then a left-button drag is delivered and three-finger swipe shortcuts are disabled.

**AM-TP-09 (P0)** — As a user, I want on-screen left/right click buttons as an alternative to taps.
- Given the "Show buttons" setting is on, Then two buttons occupy the bottom of the touchpad and act as physical buttons including press-and-hold for drag.

**AM-TP-10 (P0)** — As a user, I want sensitivity and acceleration controls so that a small phone screen can cover a large display.
- Given I change sensitivity from 1–10, Then the change applies immediately without reconnecting; Given acceleration is "Off", Then cursor travel is strictly proportional to finger travel.

**AM-TP-11 (P1)** — As Priya, I want a long-press (≥ 500 ms, no movement) to act as right-click as an alternative to two-finger tap.
- Given the option is enabled, When I press and hold, Then a haptic fires at 500 ms and a secondary click is delivered on lift.

**AM-TP-12 (P1)** — As a user, I want a quick modifier strip (⌘ ⌥ ⌃ ⇧) above the touchpad so that ⌘-click and ⇧-click work.
- Given I hold ⌘ on the strip while tapping, Then the click carries the Command flag.

### Epic GY — Gyro air-mouse mode

**AM-GY-01 (P0)** — As Marcus, I want to point the phone like a laser pointer to move the cursor.
- Given gyro mode is active and the clutch is engaged, When I rotate the phone about its yaw/pitch axes, Then the cursor moves proportionally to angular velocity with p95 latency ≤ 20 ms.

**AM-GY-02 (P0)** — As Marcus, I want a clutch (hold-to-move) so that the cursor stays still when I gesture or lower my hand.
- Given the clutch is released, Then no motion events are sent regardless of movement; the clutch is a large thumb-position button with haptic on engage/release.

**AM-GY-03 (P0)** — As Marcus, I want a recenter gesture so that drift never leaves me stuck at a screen edge.
- Given I double-tap the clutch button (or shake, if enabled), Then the cursor jumps to the center of the display the cursor is currently on.

**AM-GY-04 (P0)** — As Marcus, I want the pointer to stay still when my hand is still, even after 45 minutes.
- Given the phone is held still (|ω| < dead-zone), Then the cursor does not creep; measured drift with the phone resting on a table for 10 minutes is 0 px.

**AM-GY-05 (P0)** — As Marcus, I want tap anywhere / dedicated buttons to click in gyro mode.
- Given gyro mode, When I tap the large click area, Then a left click is delivered without moving the cursor (motion is suppressed for 80 ms around the tap).

**AM-GY-06 (P1)** — As Marcus, I want to hold the phone in either portrait or landscape and have the axes remapped automatically.
- Given the device orientation changes, Then the yaw/pitch mapping follows so that "left" is always left.

**AM-GY-07 (P1)** — As a user, I want a gyro sensitivity slider and a "smoothing" slider so that I can trade jitter for responsiveness.
- Given smoothing is at maximum, Then hand tremor is attenuated with added latency ≤ 8 ms; at minimum, no filtering beyond dead-zone.

**AM-GY-08 (P1)** — As Priya, I want a "clutch = toggle" option so that I can lock motion on for casual pointing without holding a button.

### Epic KB — Keyboard mode

**AM-KB-01 (P0)** — As Dana, I want to type on the iOS keyboard and have keystrokes appear live on the Mac.
- Given live-typing mode, When I type a character, Then it appears in the focused Mac text field within 50 ms; backspace deletes on the Mac.

**AM-KB-02 (P0)** — As Priya, I want a "compose then send" mode so that I can fix typos before they hit the Mac.
- Given commit mode, When I tap Send (or press Return with the option enabled), Then the whole string is sent as Unicode text and the field clears.

**AM-KB-03 (P0)** — As Dana, I want modifier keys (⌘ ⌥ ⌃ ⇧ fn) with latch and lock states so that shortcuts like ⌘⇧T are possible on a touch keyboard.
- Given I tap ⌘, Then it latches for the next key and releases; Given I double-tap ⌘, Then it locks until tapped again; the visual state is distinguishable without color alone.

**AM-KB-04 (P0)** — As Dana, I want Esc, Tab, arrow keys, Delete/Forward Delete, Home/End/PgUp/PgDn, and F1–F12 available.
- Given the extended key bar, Then each of those keys sends the correct virtual keycode; arrows support press-and-hold auto-repeat.

**AM-KB-05 (P0)** — As Priya, I want media keys (play/pause, next, previous, volume, mute, brightness) that work like a Mac keyboard's.
- Given a media key is tapped, Then the Mac reacts the same as the corresponding hardware key (system volume HUD appears, Now Playing app reacts).

**AM-KB-06 (P0)** — As anyone typing non-English, I want accented characters, CJK input, and emoji to arrive correctly.
- Given I type "ñ", "日本語", or "🎉", Then exactly those code points appear on the Mac regardless of the Mac's keyboard layout.

**AM-KB-07 (P1)** — As Dana, I want autocorrect and predictive text off in live-typing mode by default so that iOS never rewrites what already went to the Mac.
- Given live mode, Then the input traits disable autocorrection and prediction; Given commit mode, Then they follow the user's iOS setting.

**AM-KB-08 (P1)** — As Dana, I want a "paste text to Mac" action so that long strings (URLs, tokens) can be sent in one shot.
- Given I paste into commit mode and tap Send, Then up to 16 KB of text is delivered in order.

**AM-KB-09 (P1)** — As Dana, I want a dedicated shortcut palette (⌘Space, ⌘Tab, ⌘Q, ⌘W, ⌘⇧4, ⌘⌥Esc, screen lock) so that common shortcuts are one tap.

**AM-KB-10 (P2)** — As a user with an external keyboard attached to the iPad, I want its keys passed through to the Mac (see AM-IP-03).

### Epic PR — Presenter / media remote

**AM-PR-01 (P0)** — As Marcus, I want Next / Previous / Blank screen / Start-from-current buttons that are large and work without looking.
- Given Keynote or PowerPoint is frontmost, When I tap Next, Then the correct key (→ / Space) is sent and a haptic confirms; Blank toggles "B" (Keynote) / "B" (PowerPoint); Start sends ⌥⌘P (Keynote) / ⇧⌘Return (PowerPoint) per an app-aware profile.

**AM-PR-02 (P0)** — As Marcus, I want an on-screen timer and elapsed-time display on the phone so that I do not need to check a clock.

**AM-PR-03 (P0)** — As Priya, I want a media page with play/pause, seek ±10 s, next/previous, volume slider and mute.
- Given I drag the volume slider, Then the Mac volume updates continuously with ≤ 100 ms lag and the macOS volume HUD reflects it.

**AM-PR-04 (P1)** — As Priya, I want a row of app-launcher buttons (Plex, YouTube in Safari, Music) that I can arrange from the Mac (see Epic MC).

**AM-PR-05 (P1)** — As Marcus, I want the presenter page to show the name of the frontmost Mac app so that I know the remote's profile is correct.
- Given the frontmost application changes on the Mac, Then the phone header updates within 500 ms.

**AM-PR-06 (P2)** — As Marcus, I want a "pointer spotlight" toggle that, when on, moves the cursor with gyro while I hold the clutch and hides it when released (uses the Mac's normal cursor; no screen drawing).

### Epic MC — Custom macro buttons (defined on Mac, synced to phone)

**AM-MC-01 (P0)** — As Dana, I want to define a macro in the menu-bar helper with a name, SF Symbol icon, and an action (key combo, launch app, run Shortcut) so that the phone shows it as a button.
- Given I save a macro, Then it appears on all connected phones within 1 s and on next connect for others.

**AM-MC-02 (P0)** — As Dana, I want to record a key combination by pressing it on the Mac keyboard so that I never have to type key names.
- Given the recorder is focused, When I press ⌃⌥⌘T, Then the field shows "⌃⌥⌘T" and stores the keycode plus modifiers.

**AM-MC-03 (P0)** — As Priya, I want a "launch or activate app" action by picking an app from /Applications.
- Given the app is already running, Then it is brought to front; otherwise it is launched.

**AM-MC-04 (P1)** — As Dana, I want a "run Shortcut" action that lists my Shortcuts by name.

**AM-MC-05 (P1)** — As a security-conscious user, I want AppleScript and shell actions to be off unless I explicitly enable "Allow scripts from remote devices" per trusted device.
- Given scripts are not allowed for a device, When it triggers a script macro, Then the helper refuses and the phone shows "Blocked by Mac policy".

**AM-MC-06 (P0)** — As Priya, I want to arrange macros into pages and reorder by drag on the Mac; the phone mirrors the order.

**AM-MC-07 (P1)** — As Tomás, I want a "large buttons" layout for macros (2 columns instead of 4) selectable on the phone.

**AM-MC-08 (P1)** — As Dana, I want to export/import macros as a JSON file so that I can back them up or share them in the repo.

### Epic IP — iPad-optimized layout

**AM-IP-01 (P0)** — As Tomás, I want the iPad in landscape to show a large touchpad and a persistent keyboard/shortcut bar side by side.
- Given iPad landscape, Then the touchpad occupies ≥ 60 % width and the right pane hosts keyboard shortcuts, modifiers, and macros; the layout adapts to Split View and Stage Manager sizes without clipping.

**AM-IP-02 (P0)** — As a user, I want iPad portrait to stack touchpad above a macro/keyboard drawer.

**AM-IP-03 (P1)** — As Dana, I want a hardware keyboard attached to the iPad (Magic Keyboard, Bluetooth) to be passed through to the Mac, including modifiers and arrow keys, while Air Mouse is frontmost.
- Given an external keyboard is connected and the "Passthrough" toggle is on, When I press ⌘C, Then the Mac receives ⌘C and the iPad does not perform its own copy.
- Given a key iOS reserves (e.g., ⌘H, ⌘Tab, Globe), Then the app documents it as non-passable and the UI lists these exceptions.

**AM-IP-04 (P1)** — As a user, I want iPad pointer/trackpad input (Magic Keyboard trackpad) to be usable as a relative pointer for the Mac as an alternative to the touch surface.

**AM-IP-05 (P1)** — As Tomás, I want keyboard shortcuts on the iPad (⌘1–⌘5) to switch modes.

### Epic MB — Mac menu-bar helper

**AM-MB-01 (P0)** — As any user, I want the helper to be a menu-bar-only app (no Dock icon) that shows connection status at a glance.
- Given no device is connected, Then the icon is monochrome; Given one or more devices connected, Then the icon changes and the menu lists them with model and signal indicator.

**AM-MB-02 (P0)** — As a new user, I want an onboarding window that explains and requests Accessibility permission with a "Open System Settings" button and detects when it is granted.
- Given permission is missing, Then the helper refuses to accept input but still allows pairing, shows a persistent warning in the menu, and polls the permission state every 2 s while the window is open.

**AM-MB-03 (P0)** — As Dana, I want "Launch at login" on by default (askable during onboarding) so that a headless Mac is always reachable.

**AM-MB-04 (P0)** — As a user, I want a Trusted Devices list in the helper with name, model, first paired, last seen, and Revoke.
- Given I revoke a connected device, Then its connection is closed within 1 s and it cannot reconnect without re-pairing.

**AM-MB-05 (P0)** — As a user, I want a "Pair new device" menu item that opens the QR window, and a "Pause input" toggle for when I lend my phone.

**AM-MB-06 (P1)** — As a user, I want the helper to check GitHub Releases for updates (opt-in, once per day) and show a menu item when one is available; Homebrew installs defer to `brew upgrade`.

**AM-MB-07 (P1)** — As a user, I want the helper to show local network and firewall guidance when the macOS Application Firewall blocks incoming connections.

**AM-MB-08 (P1)** — As Ines, I want a "Diagnostics" window with live packet rate, latency histogram, dropped-datagram count, and an export-to-file button (no upload).

**AM-MB-09 (P0)** — As a user, I want the helper to display the macro editor (Epic MC) as a window reachable from the menu.

### Epic ST — Settings & personalization

**AM-ST-01 (P0)** — As a user, I want pointer sensitivity, acceleration on/off, scroll direction, scroll speed, tap-to-click, tap-and-drag, drag-lock, double-click interval, right-click gesture choice, three-finger behavior, all persistent per phone.

**AM-ST-02 (P0)** — As a user, I want gyro sensitivity, smoothing, dead-zone, clutch mode (hold/toggle), recenter gesture (double-tap/shake/both).

**AM-ST-03 (P0)** — As a user, I want keyboard mode default (live/commit), Return-sends toggle, haptics on/off, sounds on/off, keep-screen-awake while connected (default on), and dim-after-idle (default 30 s) settings.

**AM-ST-04 (P1)** — As a user, I want light/dark/system appearance and left/right-handed layout (mirrors clutch and buttons).

**AM-ST-05 (P1)** — As a user, I want to set which mode opens by default and whether the app auto-connects to the last Mac.

**AM-ST-06 (P1)** — As a user, I want a "Reset to defaults" and a settings export/import (JSON, local Files app only).

**AM-ST-07 (P1)** — As a user, I want per-Mac overrides (e.g., higher sensitivity for the TV Mac) selectable in Settings › Macs.

### Epic CR — Connection resilience

**AM-CR-01 (P0)** — As Priya, I want the app to reconnect automatically after a Wi-Fi blip.
- Given the connection drops, Then the app shows a non-blocking "Reconnecting…" banner, retries with exponential backoff (250 ms → 4 s cap), and restores the session within 3 s of network availability in ≥ 99 % of cases.

**AM-CR-02 (P0)** — As a user, I want the app to resume within 1 s after returning from the background or lock screen.
- Given the app was backgrounded for < 10 min, When it returns, Then it reuses the trusted session (resumption) and the cursor moves on the first swipe.

**AM-CR-03 (P0)** — As a user, I want the Mac to never be left with a stuck mouse button or modifier if my phone disconnects mid-drag.
- Given a drag or modifier is active, When the session times out (2 s without heartbeat), Then the helper releases all held buttons and modifiers.

**AM-CR-04 (P1)** — As Marcus, I want the app to follow the Mac when its IP changes (DHCP renewal, AP roaming) by re-resolving Bonjour and falling back to the last-known addresses.

**AM-CR-05 (P1)** — As a user, I want a clear diagnosis when the network is hostile: "Devices on this network cannot see each other (AP isolation). Try a personal hotspot."

**AM-CR-06 (P1)** — As a user, I want motion to keep flowing (degraded) over the reliable channel if UDP datagrams are being dropped by the network, with an indicator that latency may be higher.

**AM-CR-07 (P0)** — As a user, I want the app to keep the iPhone screen awake while connected and in the foreground, with an idle-dim after 30 s of no touches.

### Epic OB — Onboarding / first run

**AM-OB-01 (P0)** — As a new user, I want a three-screen intro (what it is → install the Mac helper → scan the QR) with a link/QR to the GitHub release and the `brew install --cask` command.

**AM-OB-02 (P0)** — As a new user, I want the iOS Local Network permission explained before the system prompt appears so that I do not deny it.
- Given the pre-prompt, When I tap Continue, Then the system prompt shows; Given the user denied, Then the app shows a "Fix in Settings" screen with a deep link.

**AM-OB-03 (P0)** — As a new user, I want the Mac helper's first run to walk me through Accessibility permission, launch-at-login, and show the pairing QR at the end, in one window.

**AM-OB-04 (P1)** — As a new user, I want a 20-second interactive gesture tutorial on the touchpad the first time I connect, skippable and replayable from Settings.

**AM-OB-05 (P1)** — As Marcus, I want gyro mode to prompt "hold the phone like a remote and press the clutch" on first use, with a calibration hold of 1 s.

Story count: 84 (target was 40+).

---

## 4. Functional requirements

Requirements are grouped by area; each traces to the stories above. "Host" = Mac helper; "Client" = iPhone/iPad app.

### 4.1 Discovery & pairing (FR-DP)

- **FR-DP-001** The host SHALL advertise a Bonjour service `_airmouse._tcp` (control) and `_airmouse._udp` (motion) in the local domain with TXT records: protocol version, host display name, machine model, certificate fingerprint (SHA-256, truncated 16 bytes), and a random per-install host ID. **(recommended default)**: if the architecture selects a single QUIC transport, advertise only `_airmouse._udp` and drop the TCP record; the iOS `NSBonjourServices` list must then match.
- **FR-DP-002** The client SHALL browse for these services while the Connect screen is visible or an auto-connect is pending, and SHALL stop browsing otherwise to conserve battery.
- **FR-DP-003** The QR payload SHALL be a URL of the form `airmouse://pair?v=1&id=<hostID>&n=<name>&a=<addr1,addr2,…>&p=<port>&fp=<certFP>&s=<secret>` where `s` is a 128-bit random, base64url-encoded one-time secret. The URL scheme also enables pairing from a photo of the QR opened with the Camera app. Addresses SHALL be ordered: hotspot/bridge interfaces first, then Wi-Fi, then Ethernet; link-local IPv6 included.
- **FR-DP-004** One-time secrets SHALL expire 60 s after display or on first successful use, whichever comes first, and SHALL be invalidated when the QR window closes. Failed attempts SHALL be rate-limited to 5 per minute per source IP.
- **FR-DP-005** Pairing SHALL establish mutual TLS 1.3: the host presents a self-signed certificate (Ed25519 or P-256, 10-year validity, generated on first run, private key in the login Keychain); the client generates its own key pair and self-signed certificate on first pairing (private key in Secure Enclave where available). The client SHALL prove secret knowledge with an HMAC over a TLS exporter value (channel binding) so that the secret is never transmitted and cannot be replayed onto a different session.
- **FR-DP-006** On success both sides SHALL persist the peer's certificate (pinned), display name, model, and pairing timestamp. Subsequent connections SHALL verify the peer certificate by exact match; no CA validation, no hostname validation.
- **FR-DP-007** Revocation on either side SHALL delete the stored peer certificate and terminate any active session within 1 s. Re-pairing requires a new QR.
- **FR-DP-008** The host SHALL support a maximum of 20 trusted devices and 4 simultaneous connections **(recommended default)**; input from all connected devices is merged (last event wins).
- **FR-DP-009** The client SHALL support direct connection using addresses from the QR when Bonjour discovery yields nothing (AP isolation / hotspot case).
- **FR-DP-010** All discovery and pairing UI SHALL function with Accessibility permission not yet granted on the host; only input injection is gated.

### 4.2 Touchpad mode (FR-TP)

- **FR-TP-001** The client SHALL sample touches at the display's native rate (120 Hz on ProMotion, 60 Hz otherwise) and SHALL emit one motion datagram per sample containing relative deltas in points, a monotonically increasing sequence number, and a client timestamp.
- **FR-TP-002** Gesture mapping (defaults; every mapping in the table is configurable or can be disabled in Settings unless marked fixed):

| Gesture | Default action | Notes |
|---|---|---|
| One-finger move | Move cursor | fixed |
| One-finger tap | Left click | tap: ≤ 200 ms, movement ≤ 8 pt |
| Two-finger tap | Right (secondary) click | |
| One-finger long-press (≥ 500 ms, still) | Right click | off by default; alternative for one-handed use |
| Double tap | Double click (clickState 2); triple → 3 | interval default 300 ms, range 150–600 ms |
| Tap then drag (within 300 ms) | Drag (button held) | tap-and-drag on by default |
| Drag-lock | Keep button held after lift until next tap | off by default |
| Two-finger drag | Scroll (vertical + horizontal, pixel precise) | natural direction default follows host preference (FR-TP-012) |
| Two-finger fling | Momentum scroll | decay τ ≈ 350 ms, cancelled by any touch |
| Pinch in/out (≥ 40 pt change) | Zoom out/in | see FR-TP-018 |
| Two-finger rotate | none | reserved; disabled in v1 |
| Three-finger swipe up | Mission Control (⌃↑) | mutually exclusive with three-finger drag |
| Three-finger swipe down | App Exposé (⌃↓) | |
| Three-finger swipe left/right | Switch Space (⌃→ / ⌃←) | direction follows scroll-direction setting |
| Three-finger drag | Left-button drag (window move, selection) | off by default; enabling disables swipes |
| Four-finger tap | Show Desktop (fn-F11 equivalent) | **(recommended default)**, off by default |
| Two-finger edge swipe from right edge | Notification Center (⌃⌘N is not universal; sends the Notification Center hot key configured in host) | P2, off by default |

- **FR-TP-003** Pointer sensitivity SHALL be a 1–10 integer (default 5) mapping to a base gain of 0.6× … 4.0× (points on Mac per point of finger travel at low speed), geometric spacing.
- **FR-TP-004** Pointer acceleration SHALL be applied on the host **(recommended default)** using the per-device settings the client pushes on connect and on change. Rationale: the host knows display scale, resolution, and multi-display geometry; macOS does not apply its own acceleration to synthesized absolute-position mouse events, so we must supply the curve. The curve SHALL be velocity-dependent: gain(v) = base × (1 + a × min(v / v_ref, 1)²) with a = 2.5, v_ref = 1,500 pt/s **(recommended default)**; "Acceleration off" sets a = 0. Optional presets: Precise (a = 1.0), Default, Fast (a = 4.0).
- **FR-TP-005** Sub-pixel remainders SHALL be accumulated on the host so that slow movements are not quantized to zero.
- **FR-TP-006** Cursor position SHALL be clamped to the union of the active displays' bounds; the host computes the new absolute position and posts a `mouseMoved` (or `leftMouseDragged` while a button is held) event.
- **FR-TP-007** Tap detection SHALL cancel if a second finger lands before lift (two-finger tap takes precedence) or if the finger moves > 8 pt. Palm rejection: touches with major radius above a threshold or landing at screen edges within 4 pt SHALL be ignored **(recommended default)**.
- **FR-TP-008** Click events SHALL be posted as down/up pairs with correct `clickState` and modifier flags from the modifier strip; the host SHALL apply a 15 ms minimum down duration so that apps register the click.
- **FR-TP-009** Tap-and-drag: a touch beginning within 300 ms after a tap SHALL begin a drag (`leftMouseDown` then `leftMouseDragged`); lift ends with `leftMouseUp` unless drag-lock is on.
- **FR-TP-010** Drag-lock: when enabled, lift keeps the button down; the next single tap or a 3 s no-touch timeout **(recommended default)** releases it. The UI SHALL show a visible "Dragging" indicator.
- **FR-TP-011** Scroll SHALL be posted as pixel-unit scroll-wheel events with gesture phase information (began/changed/ended and momentum phases) so that macOS apps with elastic scrolling behave as with a trackpad. Scroll speed setting 1–10 (default 5) scales pixels per point 0.5×–3×.
- **FR-TP-012** Scroll direction default SHALL be inherited from the host's "Natural scrolling" preference (read from `com.apple.swipescrolldirection`) at connect time; the client may override with Natural/Inverted explicitly.
- **FR-TP-013** Momentum scrolling SHALL be generated on the client from fling velocity (≥ 300 pt/s at lift) and SHALL decay exponentially; any new touch cancels momentum and sends a momentum-ended phase. Momentum can be disabled.
- **FR-TP-014** Two-finger scroll SHALL lock to the dominant axis when the angle is within 20° of an axis for the first 30 pt **(recommended default)**, then free-scroll; axis lock is a setting.
- **FR-TP-015** Motion SHALL be suppressed for 80 ms after a tap is recognized to avoid click-time jitter.
- **FR-TP-016** The touchpad SHALL work with the device in any orientation; the surface fills the safe area; the status bar and home indicator are hidden while touching.
- **FR-TP-017** On-screen click buttons (optional) SHALL support press-and-hold for drag and SHALL be ≥ 44 pt tall.
- **FR-TP-018** Pinch SHALL map to a "Zoom" action with configurable implementation: (a) **(recommended default)** discrete ⌘= / ⌘- keystrokes per 40 pt of pinch change, which works in browsers, Preview, Finder, and most editors; (b) ⌃+scroll for macOS Accessibility Zoom users; (c) off. Rationale: true trackpad magnify gestures cannot be synthesized with public `CGEvent` APIs; this is recorded as risk R-11.
- **FR-TP-019** Three-finger swipe shortcuts SHALL be sent as the standard keyboard shortcuts (⌃↑, ⌃↓, ⌃←, ⌃→) and SHALL be no-ops if the user has remapped them in macOS; the host MAY read the user's Mission Control shortcut settings in a later release.
- **FR-TP-020** Haptics: light impact on tap recognition, medium on right-click, selection tick on drag-lock engage; all togglable.

### 4.3 Gyro air-mouse mode (FR-GY)

- **FR-GY-001** The client SHALL use CoreMotion device-motion updates at the maximum supported rate (100 Hz on current hardware) with the `xArbitraryCorrectedZVertical` reference frame so that sensor fusion already removes gravity and slow gyro bias.
- **FR-GY-002** Pointer model: relative angular velocity → pixel delta. Per sample: Δx = −G × ω_yaw × Δt, Δy = −G × ω_pitch × Δt, where ω is the rotation rate expressed in a gravity-aligned frame (so rolling the wrist does not swap axes), Δt is the sample interval, and G is the gain in px per radian. Default G corresponds to 40° of rotation traversing a 1920 px display **(recommended default)**; sensitivity 1–10 scales G from 0.5× to 2.5×.
- **FR-GY-003** Dead zone: rotation rates below 0.5 °/s **(recommended default)** SHALL produce no motion; the threshold is adjustable 0–3 °/s. Velocity SHALL be rescaled above the threshold so there is no step discontinuity at the boundary.
- **FR-GY-004** Drift compensation: (a) rely on CoreMotion's fused attitude for gyro bias; (b) additionally, when |ω| < dead-zone for ≥ 300 ms, update a residual-bias estimate with an EMA (α = 0.05) and subtract it; (c) recenter gesture snaps the cursor to the center of the current display; (d) because the model is velocity-based (not absolute pointing), residual drift manifests as slow creep rather than offset, and (a)+(b) SHALL hold creep to 0 px when at rest.
- **FR-GY-005** Smoothing: a one-euro filter **(recommended default)** with a user-adjustable cutoff (slider "Smoothing" 0–10; 0 = raw) shall attenuate tremor with ≤ 8 ms added latency at maximum.
- **FR-GY-006** Clutch: a large (≥ 96 pt) thumb button. Modes: Hold-to-move (default) or Toggle. Motion datagrams SHALL only be sent while engaged. Engage/release fire distinct haptics. Releasing the clutch SHALL also send a "motion end" so host-side prediction stops.
- **FR-GY-007** Recenter: double-tap on the clutch (default) and/or shake gesture. Recenter is a control message; the host moves the cursor to the center of the display containing the cursor.
- **FR-GY-008** Clicking in gyro mode: a large click area (left) and secondary click area (right) above the clutch; tap = click, hold = drag while holding. Motion is suppressed 80 ms around clicks.
- **FR-GY-009** Orientation: the axis mapping SHALL follow the interface orientation (portrait, landscape-left/right) so that "pointing left" always moves left; a "lock orientation" setting exists.
- **FR-GY-010** Scrolling in gyro mode: two-finger drag on the click area scrolls; volume rocker is NOT used (App Store rules).
- **FR-GY-011** When CoreMotion reports unreliable magnetometer/attitude, the client SHALL fall back to raw gyro with bias estimation and show a subtle "calibrating" indicator; the mode SHALL never block.
- **FR-GY-012** If a device lacks a gyroscope, the Gyro tab SHALL be hidden and the Settings shall explain why.

### 4.4 Keyboard mode (FR-KB)

- **FR-KB-001** Text field passthrough: a hidden-caret text input hosts the system keyboard. In **live-typing** mode each inserted character/deletion is transmitted immediately as a key event; the local field is kept empty (or shows the last 40 characters as a fading trail for context). In **commit** mode the field accumulates text and sends on "Send" (and optionally on Return).
- **FR-KB-002** Live mode SHALL disable iOS autocorrection, predictive text, smart quotes/dashes, and auto-capitalization by default, because corrections cannot be applied retroactively on the host. Commit mode SHALL respect the user's iOS settings, and smart punctuation SHALL be a toggle in both modes.
- **FR-KB-003** Character delivery: printable ASCII and keys with a physical equivalent SHALL be delivered as virtual keycodes translated against the host's current keyboard layout (so shortcuts land on the right physical key); all other Unicode (accented, CJK, emoji, symbols) SHALL be delivered via Unicode-string keyboard events. A single grapheme cluster SHALL never be split across datagrams/messages.
- **FR-KB-004** Composed input (CJK marked text) SHALL be sent only when composition completes (commit of marked text); partial marked text SHALL not be transmitted in live mode.
- **FR-KB-005** Modifiers: ⌘, ⌥, ⌃, ⇧, fn. Tap = latch for next key; double-tap = lock; tap while locked = release. The state SHALL be shown with both color and a glyph/underline (no color-only signaling). Modifiers SHALL be sent as flag changes so that modifier-only actions (e.g., ⌘ held for a ⌘-click, ⌥ for menu alternates) work.
- **FR-KB-006** Extended keys: Esc, Tab, Return, Delete, Forward Delete, ↑↓←→, Home, End, Page Up, Page Down, Space, F1–F12 (fn-toggle for media/standard behavior). Arrow and Delete keys SHALL auto-repeat on hold (initial delay 400 ms, repeat 40 ms **(recommended default)**).
- **FR-KB-007** Media keys: play/pause, next, previous, volume up/down, mute, brightness up/down, keyboard illumination (if present). These SHALL be injected as system-defined (NX) key events so macOS handles them identically to hardware keys (volume HUD, Now Playing).
- **FR-KB-008** Shortcut palette: a configurable list of chords (defaults: ⌘Space, ⌘Tab, ⌘Q, ⌘W, ⌘Z, ⌘⇧Z, ⌘C, ⌘V, ⌘⇧4, ⌘⌥Esc, ⌃⌘Q lock). Each is one tap.
- **FR-KB-009** Text paste: strings up to 16 KB SHALL be sent as ordered Unicode segments over the reliable channel with pacing (host inserts at ≤ 500 chars/s to avoid dropped characters in slow apps; adjustable).
- **FR-KB-010** Keyboard layout awareness: the host SHALL report its current input source; when it changes, the client SHALL recompute keycode mappings.
- **FR-KB-011** Secure text: the client SHALL offer a "Secure entry" toggle that disables the fading trail and any local logging when typing passwords **(recommended default)**.
- **FR-KB-012** Caps Lock: a soft Caps Lock toggle; the host implements it as a modifier flag rather than toggling the physical Caps Lock LED state.
- **FR-KB-013** Hardware keyboards attached to iPhone/iPad SHALL be passed through when the Passthrough toggle is on (see FR-IP-004).

### 4.5 Presenter / media remote (FR-PR)

- **FR-PR-001** Presenter page buttons: Previous, Next (large, lower half), Blank/Black, Start from current slide, Exit slideshow, Pointer (gyro clutch).
- **FR-PR-002** App-aware profiles: the host SHALL report the frontmost app's bundle ID; the client SHALL choose key mappings for Keynote (`com.apple.iWork.Keynote`), PowerPoint (`com.microsoft.Powerpoint`), Google Slides in Safari/Chrome (URL not visible; fallback to generic), Preview/PDF (generic arrows). Generic profile uses → / ← / B / Esc.
- **FR-PR-003** Timer: start/pause/reset stopwatch plus optional countdown with a gentle haptic at 5 and 1 minutes remaining.
- **FR-PR-004** Media page: play/pause, previous, next, seek −10/+10 s (sends ← / → or J/L per profile for YouTube in browser), volume slider (continuous, 0–100 in 1/16 steps matching macOS), mute, and a Now Playing title if the host can read it via MediaRemote-free means (menu bar Now Playing is private API → **v1 shows only frontmost app name**).
- **FR-PR-005** Volume slider changes SHALL be sent as absolute volume set messages (control channel) so the slider and Mac never disagree; the host uses system-defined key events (16 steps) or CoreAudio to set volume **(recommended default: CoreAudio for the default output device, falling back to key events)**.
- **FR-PR-006** App launcher row: up to 8 macros of type `launchApp` flagged "show on media page".
- **FR-PR-007** Presenter mode SHALL keep the phone screen on and dim to 20 % brightness after 10 s without touch (configurable) to save battery during long talks.

### 4.6 Custom macros (FR-MC)

- **FR-MC-001** Macro data model (JSON, shared Swift package `Codable`):

| Field | Type | Constraints |
|---|---|---|
| `id` | UUID | stable across edits |
| `name` | String | 1–24 characters, unique per host |
| `icon` | String | SF Symbol name; validated on both sides; fallback `command` symbol if unknown on the client's OS |
| `tint` | String? | one of 12 named accent colors |
| `action` | enum | exactly one of the action kinds below |
| `pages`/`order` | Int, Int | page 0–5, order within page |
| `showOnMediaPage` | Bool | launcher row eligibility |
| `requiresConfirmation` | Bool | phone asks "Run <name>?" before firing (default false; forced true for script kinds) |
| `createdAt`, `updatedAt` | Date | |

Action kinds: `keyCombo { modifiers: Set<Modifier>, keyCode: UInt16, keyLabel: String }`; `keySequence { steps: [keyCombo or text], interStepDelayMs }` (max 16 steps); `launchApp { bundleID, activateIfRunning: Bool }`; `openURL { url }`; `runShortcut { name }`; `appleScript { source }` (≤ 8 KB); `shellCommand { command }` (≤ 2 KB). Script kinds are gated by FR-MC-006.

- **FR-MC-002** Macros SHALL be authored only on the host (menu-bar helper macro editor) in v1; the client is read-only **(recommended default; matches "synced from Mac")**. Sync direction: host → client. The full macro set is sent on connect and on every change (small: ≤ 64 macros × ~1 KB).
- **FR-MC-003** Limits: 64 macros per host, 6 pages × up to 12 per page, names ≤ 24 chars, sequences ≤ 16 steps.
- **FR-MC-004** Key recorder: the editor SHALL capture a chord from the physical keyboard, showing the macOS glyph string. Recording SHALL use a local event monitor while the editor window is key (no global Input Monitoring).
- **FR-MC-005** `launchApp` SHALL use `NSWorkspace.openApplication(at:configuration:)`; `runShortcut` SHALL use the `shortcuts run` CLI or Shortcuts Events scripting; `openURL` SHALL use `NSWorkspace.open`.
- **FR-MC-006** `appleScript` and `shellCommand` SHALL be disabled by default. Enabling requires (a) a global "Allow script macros" toggle in the helper, and (b) a per-trusted-device "Allow scripts" checkbox. The phone SHALL show a distinct icon badge on script macros and always confirm before firing.
- **FR-MC-007** Execution results (success/failure and a ≤ 120-char message) SHALL be returned to the client to show a toast.
- **FR-MC-008** Export/import: JSON file via a Save/Open panel; import validates schema version and de-duplicates by `id`.
- **FR-MC-009** The client SHALL cache the last received macro set per host so buttons render instantly on reconnect; stale sets are replaced on sync.
- **FR-MC-010** A default starter set SHALL be created on first run: Mission Control, Show Desktop, Screenshot (⌘⇧4), Lock Screen, Spotlight, Terminal, Safari, Music.

### 4.7 iPad layout (FR-IP)

- **FR-IP-001** Size-class-driven layouts: compact width → phone layout; regular width landscape → split (touchpad ≥ 60 % + side panel with tabs: Keys, Macros, Presenter); regular width portrait → stacked with a resizable drawer.
- **FR-IP-002** Layout SHALL remain functional at Split View 1/3 width and Stage Manager minimum window size; the touchpad SHALL never be smaller than 320 × 240 pt.
- **FR-IP-003** Pointer devices connected to the iPad (trackpad/mouse) SHALL optionally drive the Mac cursor via relative deltas (`UIPointerInteraction`/GameController mouse APIs) when the "Use iPad trackpad" toggle is on.
- **FR-IP-004** External hardware keyboard passthrough: when on and the app is frontmost, all key presses including modifiers SHALL be forwarded and not handled locally, except keys iOS reserves (Globe/fn, ⌘H, ⌘Tab, ⌘Space when Spotlight is bound, ⌘⇧3/4 screenshot, volume/power). The list SHALL be shown in Settings.
- **FR-IP-005** iPad keyboard shortcuts ⌘1…⌘5 switch modes; ⌘K focuses the keyboard field; these are suspended while Passthrough is on.
- **FR-IP-006** Apple Pencil hover/contact SHALL be treated as a one-finger touch (no pressure semantics).

### 4.8 Mac menu-bar helper (FR-MB)

- **FR-MB-001** The helper SHALL be an `LSUIElement` (agent) app: menu-bar icon only, no Dock icon, no main window on launch after onboarding.
- **FR-MB-002** Menu contents: status line, connected devices (with Disconnect), "Pair new device…", "Pause input" toggle, "Macros…", "Trusted Devices…", "Diagnostics…", "Settings…", "Check for updates…", "Quit".
- **FR-MB-003** Permissions onboarding: detect `AXIsProcessTrusted()`; show explanation ("Air Mouse needs Accessibility to move the cursor and type on your behalf; it never reads your screen or your keystrokes"), button to open the Privacy & Security › Accessibility pane, and poll every 2 s. State SHALL survive relaunch and re-prompt if the permission is later revoked (e.g., after an app update changes the code signature).
- **FR-MB-004** Launch at login via `SMAppService.mainApp` with a checkbox; default on, set during onboarding.
- **FR-MB-005** Trusted Devices window: table of device name, model, iOS version, first paired, last seen, "Allow scripts" checkbox, Revoke button; rename device locally.
- **FR-MB-006** "Pause input" SHALL drop all input from clients but keep sessions alive and inform clients so they show a "Paused on Mac" banner.
- **FR-MB-007** Update check: opt-in, once per 24 h, GET to GitHub Releases API only; Homebrew-installed builds SHALL show `brew upgrade --cask air-mouse` instead of downloading.
- **FR-MB-008** Diagnostics window: live rate of motion datagrams, RTT histogram, drop/reorder counters, current cipher, peer certificate fingerprint, and "Export diagnostics…" (local file). No automatic upload.
- **FR-MB-009** The helper SHALL release all held buttons/modifiers and stop injection on quit, sleep, and on Accessibility permission loss.
- **FR-MB-010** The helper SHALL detect the macOS Application Firewall blocking incoming connections (connection attempts observed via Bonjour but no handshake completes) and offer guidance.
- **FR-MB-011** The helper SHALL support multiple displays: cursor clamps to the union of displays and recenter uses the display under the cursor.

### 4.9 Settings & personalization (FR-ST)

- **FR-ST-001** All settings SHALL persist locally (UserDefaults / App Group), export/import as JSON, and SHALL never leave the device except the input-affecting subset pushed to the host per session (sensitivity, acceleration, scroll direction/speed, tap timing).
- **FR-ST-002** Per-host overrides SHALL layer over global settings.
- **FR-ST-003** Settings screens SHALL include inline explanations and a live preview area for the touchpad settings.
- **FR-ST-004** Haptics, sounds, keep-awake, idle-dim, appearance, handedness, default mode, auto-connect, gesture toggles (each gesture individually), and tutorial replay SHALL be available.

### 4.10 Connection resilience (FR-CR)

- **FR-CR-001** Two channels: a **reliable, ordered control channel** (pairing, settings, macros, key events, clicks, volume, app info, heartbeats) and an **unreliable motion channel** (cursor deltas, scroll deltas, gyro deltas) — both encrypted and authenticated with keys bound to the TLS 1.3 session. **(recommended default)**: implement both over QUIC via Network.framework (streams for control, RFC 9221 DATAGRAM frames for motion), which gives one handshake, 0-RTT/session resumption for fast reconnect, connection migration, and built-in encryption. Alternative if QUIC is rejected: TLS 1.3 over TCP for control plus DTLS 1.3 (or an AEAD keyed via TLS exporter) over UDP for motion.
- **FR-CR-002** Motion datagrams SHALL carry a 32-bit sequence number; the host SHALL discard out-of-order datagrams older than the latest by more than 8 and SHALL treat gaps > 100 ms as a motion pause (stop prediction).
- **FR-CR-003** Clicks, key events, and modifier changes SHALL always use the reliable channel so nothing is lost or duplicated.
- **FR-CR-004** Heartbeat every 500 ms on the control channel; session timeout after 2 s → host releases held inputs (FR-MB-009) and client shows "Reconnecting…".
- **FR-CR-005** Reconnect with exponential backoff 250 ms, 500 ms, 1 s, 2 s, 4 s (cap), jittered, indefinitely while the app is foregrounded; on success, the client re-pushes settings and the host re-sends macros and app state.
- **FR-CR-006** Fast resume from background: sessions SHALL be resumable (session tickets / 0-RTT) so that returning from the lock screen re-establishes the encrypted session in ≤ 1 s on a warm network.
- **FR-CR-007** Address change handling: on loss, the client SHALL re-resolve Bonjour, then try the last-known addresses, then QR addresses.
- **FR-CR-008** UDP-blocked fallback: if ≥ 90 % of motion datagrams are unacknowledged (probe-based) for 3 s, the client SHALL route motion over the reliable channel with coalescing and show an "Elevated latency" badge; it SHALL periodically probe to switch back.
- **FR-CR-009** The client SHALL keep the screen awake (idle timer disabled) while connected and foregrounded; after 30 s without touch it SHALL dim the UI (not the system brightness) and restore on touch.
- **FR-CR-010** Host-side prediction/smoothing: the host MAY extrapolate cursor motion by at most one sample interval when a datagram is late, and SHALL never extrapolate beyond 16 ms.
- **FR-CR-011** Local-only guarantee: the client SHALL refuse to connect to non-private (public) IP ranges unless the address came from a QR scan.

### 4.11 Onboarding (FR-OB)

- **FR-OB-001** iOS first run: 3 pages (value proposition; install the Mac helper with a scannable QR to the GitHub Releases page and the Homebrew command; pre-permission explanation for Local Network), then camera for QR pairing.
- **FR-OB-002** The Local Network system prompt SHALL be triggered only after the user taps Continue on the explanation page. Denial handling: a dedicated screen with a deep link to Settings and re-check on return.
- **FR-OB-003** Camera permission is requested only when the QR scanner opens; denial offers a "paste pairing link" alternative (the `airmouse://` URL).
- **FR-OB-004** Mac first run: single window with steps: Accessibility → Launch at login → Firewall note (if enabled) → Show QR. Completion is stored; the flow is re-enterable from the menu.
- **FR-OB-005** First-connect gesture tutorial (touchpad): 5 steps (move, tap, two-finger tap, scroll, pinch), each verified by detecting the gesture; skippable; replay from Settings.
- **FR-OB-006** Gyro first use: instruction card + 1 s still-hold calibration to seed the bias estimator.

---

## 5. Non-functional requirements

### 5.1 Performance (NFR-PERF)

- **NFR-PERF-001** End-to-end motion latency (touch or IMU sample → `CGEvent` post): p50 ≤ 12 ms, p95 ≤ 20 ms on 5 GHz Wi-Fi with the Mac and phone on the same AP. Budget per hop **(recommended default)**:

| Hop | Budget (p95) | Notes |
|---|---|---|
| Sensor sample → app callback (touch 120 Hz / IMU 100 Hz) | 4 ms | half a frame interval on average plus delivery |
| Client gesture recognition, filtering, encoding | 1 ms | no allocations on the hot path |
| Encryption + datagram send | 0.5 ms | AEAD per datagram, ≤ 64 bytes payload |
| Wi-Fi air time + AP forwarding | 6 ms | dominant and least controllable; 2.4 GHz will exceed this |
| Host receive, decrypt, decode, acceleration curve | 0.5 ms | dedicated high-priority thread |
| `CGEvent` post → WindowServer cursor update | 2 ms | |
| **Total** | **14 ms** | leaves 6 ms headroom against the 20 ms target; display scan-out is not counted |

- **NFR-PERF-002** Throughput: the client SHALL sustain 120 motion datagrams/s (ProMotion) plus 100 gyro samples/s without coalescing; when the network is congested it SHALL coalesce to ≥ 60/s rather than queue (never buffer more than 2 samples).
- **NFR-PERF-003** Jitter: p95 inter-event interval on the host ≤ 12 ms at 120 Hz input.
- **NFR-PERF-004** Control-channel actions (click, key) SHALL be delivered in ≤ 30 ms p95.
- **NFR-PERF-005** Cold start to touchpad-ready (trusted host in range): ≤ 2 s on iPhone 13-class devices.
- **NFR-PERF-006** Host CPU ≤ 3 % of one core at 120 Hz input on Apple silicon; memory ≤ 60 MB. Client CPU ≤ 15 % during active use.
- **NFR-PERF-007** Battery: ≤ 8 %/h in touchpad mode and ≤ 12 %/h in gyro mode (M6), with screen at 50 % and dim-after-idle enabled; CoreMotion updates SHALL stop when gyro mode is not visible.

### 5.2 Reliability (NFR-REL)

- **NFR-REL-001** Auto-reconnect within 3 s of network availability for ≥ 99 % of interruptions < 10 s (M4).
- **NFR-REL-002** No stuck input: 100 % of session losses during drag/modifier hold SHALL release inputs within 2.5 s.
- **NFR-REL-003** Crash-free sessions ≥ 99.5 % (M3). The helper SHALL be relaunched by launchd if it crashes (KeepAlive via login item semantics where available).
- **NFR-REL-004** The helper SHALL run unattended for ≥ 30 days without memory growth > 10 MB.
- **NFR-REL-005** Protocol versioning: both sides SHALL negotiate a protocol version; mismatches SHALL produce a human-readable "update the Mac helper / the app" message, never a silent failure.

### 5.3 Security (NFR-SEC)

- **NFR-SEC-001** All traffic SHALL be encrypted and authenticated with TLS 1.3 (or QUIC's TLS 1.3); no plaintext fallback; cipher suites limited to AEAD suites (AES-GCM, ChaCha20-Poly1305).
- **NFR-SEC-002** Mutual authentication with pinned self-signed certificates on both sides (FR-DP-005/006). No CA, no cloud, no accounts.
- **NFR-SEC-003** One-time pairing secret: 128-bit random, 60 s lifetime, single use, bound to the TLS channel via exporter-based HMAC; never transmitted in the clear or reused.
- **NFR-SEC-004** Replay protection: TLS/QUIC record protection for the control channel; per-datagram sequence numbers with a sliding anti-replay window (size 64) for motion; nonces never reused within a session; sessions re-key on resumption.
- **NFR-SEC-005** Private keys SHALL be stored in the Keychain (Secure Enclave-backed on iOS where available; login Keychain, non-exportable, on macOS) and SHALL never be logged or exported.
- **NFR-SEC-006** Local-only: the app and helper SHALL make no network requests other than the peer connection, Bonjour, and (opt-in, host only) the GitHub Releases update check.
- **NFR-SEC-007** Script macros are opt-in per device (FR-MC-006); the helper SHALL never execute arbitrary code received from a client — only macros defined locally on the Mac may run.
- **NFR-SEC-008** Rate limiting of failed handshakes (5/min/IP) and pairing attempts; no user-enumerable error details.
- **NFR-SEC-009** Secure coding: Swift with no `unsafe` on the parsing path; fuzz tests for protocol decoding in CI; dependency count minimized (Network.framework, CryptoKit, no third-party networking).
- **NFR-SEC-010** No telemetry by default. Optional diagnostics are local files the user can share manually. Crash reporting relies on Apple's opt-in system reporting; no third-party SDKs.
- **NFR-SEC-011** A `SECURITY.md` with a private disclosure channel and a 90-day coordinated disclosure policy SHALL exist at launch.
- **NFR-SEC-012** Threat model documented in the repo: attacker on the same LAN (passive & active), stolen phone, malicious QR, rogue helper impersonation. Each SHALL map to a mitigation above.

### 5.4 Privacy (NFR-PRIV)

- **NFR-PRIV-001** App Privacy "nutrition label" answers **(recommended default)**: *Data Not Collected*. No identifiers, no usage data, no diagnostics collected by the developer. If the owner later adds opt-in diagnostics, this changes to "Diagnostics — not linked to you — optional".
- **NFR-PRIV-002** iOS permission strings: `NSLocalNetworkUsageDescription` — "Air Mouse finds and connects to your Mac on your local network. Nothing is sent over the internet."; `NSCameraUsageDescription` — "The camera is used only to scan the pairing QR code shown on your Mac."; `NSMotionUsageDescription` is not required for CoreMotion gyro/accelerometer, but the app SHALL still explain the sensor use in Settings.
- **NFR-PRIV-003** macOS Accessibility explanation (shown in onboarding and README): Accessibility is required because posting synthetic mouse and keyboard events with `CGEvent` is gated by this permission on macOS 10.14+. Air Mouse does **not** request Input Monitoring (it never observes local keystrokes; macro recording uses a local monitor only while the editor window is key), does **not** request Screen Recording, and does **not** read screen content.
- **NFR-PRIV-004** Typed text SHALL never be persisted on either side beyond in-memory buffers required for delivery; the fading trail is off in Secure entry mode.
- **NFR-PRIV-005** Diagnostics exports SHALL redact typed text and contain only timing/network counters.

### 5.5 Accessibility (NFR-A11Y)

- **NFR-A11Y-001** All controls SHALL have VoiceOver labels, hints, and traits; the touchpad surface SHALL be a custom accessibility element that announces mode and supports the "escape" gesture to reach other controls.
- **NFR-A11Y-002** Dynamic Type up to the accessibility XXXL size SHALL not clip; buttons grow accordingly.
- **NFR-A11Y-003** Haptics and sounds SHALL be individually togglable; Reduce Motion SHALL disable decorative animation.
- **NFR-A11Y-004** Color SHALL never be the sole state signal; contrast ≥ 4.5:1 for text and ≥ 3:1 for controls; high-contrast mode respected.
- **NFR-A11Y-005** Tap timing, double-click interval, long-press duration, and dead zones SHALL be user-adjustable (Tomás).
- **NFR-A11Y-006** Every gesture SHALL have a non-gesture alternative (on-screen buttons, shortcut palette, macros).
- **NFR-A11Y-007** The Mac helper UI SHALL be fully keyboard-navigable and VoiceOver-labeled.

### 5.6 Localization (NFR-L10N)

- **NFR-L10N-001** All user-visible strings SHALL be in String Catalogs; no concatenated sentences; plurals via the catalog.
- **NFR-L10N-002** Ship English at launch; the repo SHALL accept community translations via pull request with a documented process. Right-to-left layouts SHALL not break the touchpad (mirroring disabled for the surface, enabled for chrome).
- **NFR-L10N-003** Key labels SHALL use the macOS glyph conventions (⌘⌥⌃⇧) independent of locale; key names SHALL localize.

### 5.7 Open source (NFR-OSS)

- **NFR-OSS-001** License: **MIT (recommended default)**. Rationale: permissive as required, shortest and most familiar to the Swift/iOS community, minimal friction for contributors and for the App Store. Alternative: Apache-2.0 if the owner wants an explicit patent grant; the choice must be made before the first public commit.
- **NFR-OSS-002** Repository essentials at launch: `README.md` (with 30-second demo GIF and install instructions), `LICENSE`, `CONTRIBUTING.md` (build steps, code style via SwiftFormat/SwiftLint configs, PR checklist, how to add a macro action type), `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md`, issue and PR templates, `docs/` with the protocol specification.
- **NFR-OSS-003** Monorepo with three targets: `AirMouse-iOS`, `AirMouse-Mac`, and the shared `AirMouseProtocol` Swift package (wire format, Codable models, gesture math, tests) as decided.
- **NFR-OSS-004** CI (GitHub Actions, macOS runners): build both apps, run unit tests for the protocol package (including fuzzing of decoders), SwiftLint, and a headless integration test that pairs a simulated client to the helper and asserts synthesized events on a virtual display. CI SHALL run on forks without secrets.
- **NFR-OSS-005** Reproducible builds: pinned Xcode version via `.xcode-version`, no third-party binary dependencies, release builds produced by a tagged CI workflow; the Mac release is notarized and its SHA-256 published alongside the artifact and used in the Homebrew cask.
- **NFR-OSS-006** Signing secrets live in GitHub Actions secrets owned by the project owner; contributors build unsigned for the simulator/local Mac.
- **NFR-OSS-007** Semantic versioning; protocol version is independent and documented in `docs/protocol.md`.

### 5.8 macOS-specific (NFR-MAC)

- **NFR-MAC-001** Menu-bar-only agent, macOS 15+, Apple silicon and Intel (universal binary) **(recommended default: universal)**.
- **NFR-MAC-002** Launch at login via `SMAppService`; the user can toggle it from the helper or System Settings › Login Items.
- **NFR-MAC-003** Permissions: `CGEvent` posting requires Accessibility (Privacy & Security › Accessibility). Note for contributors: a sandboxed Mac App Store app *can* post `CGEvent`s once the user grants Accessibility, but v1 distribution is direct — notarized Developer ID builds via GitHub Releases and a Homebrew cask — so the helper is **not sandboxed (recommended default)**, uses Hardened Runtime, and is notarized. Not sandboxing keeps `launchApp`, `runShortcut`, and optional script macros simple and avoids entitlement negotiations. Mac App Store distribution is a future option and would require sandboxing and removing script macros.
- **NFR-MAC-004** Local network privacy on macOS 15: the helper SHALL include `NSLocalNetworkUsageDescription` and `NSBonjourServices` in its Info.plist because macOS Sequoia gates local-network access for apps that browse or send to local hosts; advertising and accepting connections should not trigger the prompt, but the update check and Bonjour re-registration paths must not break if it appears.
- **NFR-MAC-005** The helper SHALL cope with the Application Firewall ("Allow incoming connections" prompt) and document it.
- **NFR-MAC-006** Event injection SHALL happen on a dedicated thread with `.userInteractive` QoS; `CGEvent` posting to `.cghidEventTap`.
- **NFR-MAC-007** Sleep/wake: on system sleep, sessions are closed cleanly; on wake, Bonjour re-registers within 2 s.

---

## 6. Platform constraints & assumptions

| # | Constraint / assumption | Consequence for the product |
|---|---|---|
| C1 | Minimum iOS 18 / iPadOS 18 / macOS 15 (decided) | Allows Swift 6 concurrency, String Catalogs, `SMAppService`, Network.framework QUIC datagrams, SwiftUI `@Observable`. Devices without gyroscope (some iPads) hide Gyro mode. |
| C2 | iOS apps cannot act as a Bluetooth HID peripheral (decided) | No Bluetooth transport; both devices must share an IP network (Wi-Fi, or iPhone personal hotspot with the Mac joined to it). |
| C3 | iOS background execution: sockets are suspended shortly after the app leaves the foreground; no background mode exists for "remote control" | The connection is intentionally foreground-only. The app disables the idle timer while connected, dims its own UI when idle, and relies on fast session resumption (≤ 1 s) when returning. The Mac helper treats a silent client as disconnected after 2 s and releases inputs. No lock-screen or Control Center controls in v1. |
| C4 | iOS Local Network privacy prompt (iOS 14+) is shown on first Bonjour browse/local connection and can be denied | Pre-permission explanation screen (FR-OB-002); denial detection and Settings deep link; `NSLocalNetworkUsageDescription` and `NSBonjourServices` (`_airmouse._tcp`, `_airmouse._udp`) are mandatory in Info.plist or discovery silently fails. |
| C5 | macOS 15 also has a local network privacy prompt | Helper declares the same keys (NFR-MAC-004). |
| C6 | `CGEvent` posting requires Accessibility permission; the permission is tied to the code signature | Onboarding (FR-MB-003); re-prompt after updates if the signature changes; document for Homebrew users. |
| C7 | Trackpad-native gestures (magnify, rotate, swipe) cannot be synthesized with public APIs | Pinch and swipes are mapped to keyboard shortcuts (FR-TP-018/019); documented limitation. |
| C8 | macOS applies no acceleration to synthesized absolute mouse positions | The host implements the acceleration curve (FR-TP-004). |
| C9 | Media keys require system-defined (NX) events, not plain `CGEvent` key codes | FR-KB-007; uses `NSEvent.otherEvent(with:.systemDefined…)` → `CGEvent`. |
| C10 | The iOS client must be distributed via the App Store (or TestFlight/EU alternative marketplaces) for the general public; sideloading is developer-only | App Store review constraints apply to the client (see R-08); the Mac helper is distributed directly. |
| C11 | CoreMotion device-motion max rate is ~100 Hz | Gyro mode runs at 100 Hz; touch runs at 120 Hz on ProMotion. |
| C12 | Wi-Fi 2.4 GHz and mesh networks add 10–30 ms of jitter | The 20 ms target is specified for 5 GHz on a single AP; the app shows a latency indicator rather than pretending. |
| C13 | Consumer routers and enterprise Wi-Fi may block multicast (mDNS) or isolate clients | QR direct-connect fallback (FR-DP-009), hotspot guidance (FR-CR-005 story). |
| C14 | Homebrew cask requires a stable download URL and SHA-256 per release | Release workflow publishes both (NFR-OSS-005). |

---

## 7. Out of scope for v1 and future work

### 7.1 Explicitly out of v1 scope
- Multi-Mac switching (fast switch between several paired Macs from one screen). Pairing with multiple Macs is allowed, but switching is a manual pick from the Connect screen. (decided)
- Apple Watch companion. (decided)
- Bluetooth of any kind (HID impossible on iOS; BLE data channel not worth the latency). (decided)
- Any cloud relay, account system, or internet connectivity between devices.
- Screen preview / thumbnail streaming from the Mac to the phone.
- Clipboard sync, file drop, or URL hand-off.
- Windows/Linux host; Android client.
- Absolute-pointing gyro mode (pointing at a specific screen location using camera/UWB).
- Mac App Store distribution of the helper.
- Editing macros on the phone (phone is read-only for macros in v1).
- Widgets, Lock Screen controls, Control Center controls, Shortcuts actions on iOS, Siri integration.

### 7.2 Future list (candidates, unordered)
1. Multi-Mac switching with a swipe-down picker and per-Mac accent colors.
2. Apple Watch companion (presenter next/prev, media keys) via the phone as a relay.
3. Windows and Linux hosts (the protocol package makes this a host-side port; contributors likely).
4. Android client.
5. Bluetooth fallback data channel (non-HID) for networks that forbid device-to-device traffic.
6. Clipboard sync (bidirectional, explicit user action).
7. File drop (phone → Mac Downloads).
8. Screen preview / low-rate thumbnail streaming for headless Macs (requires Screen Recording permission — separate opt-in).
9. Vision Pro client (trackpad on a floating panel; gaze-based pointing).
10. Phone-side macro editing and per-app macro pages that switch automatically with the frontmost app.
11. Absolute pointing via UWB/Camera for presenters.
12. Mac App Store build of the helper (sandboxed, no script macros).
13. Per-app touchpad profiles (e.g., inverted scroll only in a specific app).
14. Wake-on-LAN packet from the phone to wake a sleeping Mac.

---

## 8. Open questions & risks register

Likelihood/Impact: L = Low, M = Medium, H = High.

| ID | Risk / question | Likelihood | Impact | Mitigation / decision needed |
|---|---|---|---|---|
| R-01 | **Gyro drift and jitter** make air-mouse feel unusable in long presentations | M | H | Velocity-based mapping (drift → slow creep, not offset), CoreMotion fused frame, stillness bias estimation, dead zone, one-euro smoothing, clutch + recenter; measure creep in lab (target 0 px at rest). |
| R-02 | **UDP blocked or heavily shaped** by some routers/enterprise Wi-Fi; multicast (mDNS) blocked; **AP/client isolation** | M | H | QR carries direct addresses; reliable-channel fallback for motion with "elevated latency" badge; hotspot guidance; document network requirements. |
| R-03 | **iOS Local Network permission denied** or the prompt confuses users | M | H | Pre-permission explanation, deep link to Settings, detect denial; test the copy in usability sessions. |
| R-04 | **Accessibility permission friction on macOS**: users do not find the toggle, or it resets after updates (signature change), or is greyed out under MDM | H | H | Guided onboarding with polling; stable Developer ID signing; documented MDM PPPC profile for managed Macs; menu-bar warning state. |
| R-05 | **TLS handshake / reconnect time** exceeds the 1–3 s resume targets on lossy networks | M | M | QUIC 0-RTT / TLS session resumption; keep resumption tickets for 24 h; connection migration on IP change; measure in CI with simulated loss. |
| R-06 | **20 ms latency target not achievable** on 2.4 GHz or mesh networks | H | M | Target specified for 5 GHz; in-app latency indicator; coalescing and host prediction bounded at 16 ms; recommend 5 GHz in onboarding. |
| R-07 | **Pinch/zoom and system gestures** cannot be synthesized natively; keyboard-shortcut mapping feels inconsistent across apps | H | M | Ship shortcut mapping with per-gesture toggles; document; investigate private gesture event fields as a non-default experimental option in a later release. |
| R-08 | **App Store review** of a "remote control / keyboard" app: reviewer cannot test without the Mac helper; concerns about "hidden features" or running code | M | H | Provide reviewer notes with a demo video and a TestFlight-linked Mac build; keep all functionality visible; no code download; script macros execute only Mac-defined content. Budget one rejection cycle in the plan. |
| R-09 | **Name collision**: "Air Mouse" is already used by several App Store apps and a hardware category; potential trademark conflict and App Store name rejection | H | H | **Recommend a trademark search (USPTO, EUIPO, WIPO) before public launch and pick a distinctive working name**; candidates: "Waft", "Glidepad", "Hover Remote" **(recommended: choose one before the repo goes public; keep "Air Mouse" as the internal codename)**. Also verify the App Store name availability early via App Store Connect. |
| R-10 | **Bonjour service type naming**: `_airmouse` may already be registered/used by other apps, causing cross-talk | L | M | Register a distinct service type with IANA (e.g., `_airmouse-oss`) or namespace by host ID in TXT; ignore records without our protocol version tag. |
| R-11 | **Key-code translation across layouts** (Dvorak, non-US) produces wrong shortcuts | M | M | Translate via the host's current input source (FR-KB-010); Unicode path for text; automated tests with several layouts. |
| R-12 | **Stuck inputs** if the host crashes mid-drag | L | H | Release-all on every exit path; watchdog thread; integration test. |
| R-13 | **Battery drain** from 120 Hz touch + Wi-Fi + screen-on exceeds targets | M | M | Idle dim, stop motion sending when finger lifted, stop CoreMotion when not in gyro mode, coalesce when no movement; measure early. |
| R-14 | **Homebrew cask acceptance** (homebrew-cask requires notability thresholds for new casks) | M | L | Start with a project tap (`brew tap owner/airmouse`); apply to homebrew-cask after adoption. |
| R-15 | **Script macros as an attack vector** (a compromised phone runs shell commands on the Mac) | L | H | Off by default, per-device opt-in, confirmation on phone, macros only defined on the Mac, clear warnings; documented in the threat model. |
| R-16 | **iPad hardware keyboard passthrough** cannot capture iOS-reserved keys and may conflict with system shortcuts | H | L | Document exceptions in-app; treat as best-effort (P1). |
| R-17 | **Open question**: should the client be allowed to edit macros in v1? | — | M | Recommendation: no (host-only authoring) to keep the sync model one-directional and simple; revisit after launch. |
| R-18 | **Open question**: QUIC (single transport) vs TCP+UDP/DTLS | — | M | Recommendation: QUIC via Network.framework; architecture doc must validate datagram support and measured handshake times on iOS 18/macOS 15 before committing. |
| R-19 | **Open question**: license MIT vs Apache-2.0 | — | L | Recommendation MIT; owner to confirm before first public commit. |
| R-20 | **Open question**: universal binary (Intel + Apple silicon) for the helper | — | L | Recommendation: universal; costs little, widens reach on macOS 15-capable Intel Macs. |

---

## 9. Glossary

| Term | Meaning |
|---|---|
| **Host / helper** | The macOS menu-bar application that advertises itself, accepts paired connections, and injects input via `CGEvent`. |
| **Client** | The iPhone/iPad app. |
| **Bonjour / mDNS / DNS-SD** | Apple's zero-configuration service discovery over multicast DNS; used to find the host on the LAN. |
| **Service type** | The DNS-SD name of a service, e.g. `_airmouse._udp`; must be declared in `NSBonjourServices` on iOS. |
| **Pairing** | One-time process establishing mutual trust between a client and host using a QR-delivered secret and certificate pinning. |
| **One-time secret** | 128-bit random value embedded in the QR, valid 60 s, single use, proven via HMAC over a TLS exporter. |
| **Certificate pinning** | Accepting a peer only if its certificate exactly matches one stored at pairing time; no certificate authorities involved. |
| **mTLS** | Mutual TLS — both client and server present certificates. |
| **TLS exporter / channel binding** | A key derived from the TLS session, used to bind the pairing proof to this specific encrypted connection. |
| **QUIC** | UDP-based transport with built-in TLS 1.3, streams, and (RFC 9221) unreliable datagrams; recommended single transport. |
| **DTLS** | Datagram TLS; alternative encryption for UDP if QUIC is not used. |
| **Control channel** | Reliable, ordered channel for clicks, keys, settings, macros, heartbeats. |
| **Motion channel** | Unreliable datagram channel for high-rate cursor/scroll/gyro deltas. |
| **AEAD** | Authenticated encryption with associated data (AES-GCM, ChaCha20-Poly1305). |
| **Replay protection** | Rejecting duplicated or re-sent packets via sequence numbers and a sliding window. |
| **CGEvent** | Core Graphics event API used to synthesize mouse and keyboard events on macOS; requires Accessibility permission. |
| **Accessibility permission** | macOS Privacy & Security setting allowing an app to control the computer (post events). |
| **Input Monitoring** | Separate macOS permission for observing keystrokes; *not* required by Air Mouse. |
| **LSUIElement** | Info.plist flag making a macOS app menu-bar-only (no Dock icon). |
| **SMAppService** | macOS 13+ API for registering login items. |
| **Notarization** | Apple's malware scan for directly distributed Mac apps; required for Gatekeeper to allow launch. |
| **Homebrew cask** | Homebrew formula type for distributing macOS GUI apps. |
| **Acceleration curve** | Function mapping input velocity to pointer gain. |
| **Dead zone** | Angular-velocity threshold below which gyro motion is ignored. |
| **Drift** | Slow unintended cursor motion caused by gyro bias. |
| **Clutch** | Hold-to-move button in gyro mode; motion only sent while engaged. |
| **Recenter** | Gesture that snaps the cursor to the display center. |
| **One-euro filter** | Adaptive low-pass filter that trades jitter for lag depending on speed. |
| **Tap-and-drag / drag-lock** | Trackpad behaviours allowing drag without continuous pressure. |
| **Natural scrolling** | Content follows finger direction (macOS default); inverted is the opposite. |
| **Momentum scrolling** | Continued decelerating scroll after a fling. |
| **Live-typing vs commit mode** | Sending each keystroke immediately vs composing locally and sending once. |
| **Macro** | A user-defined button on the phone, authored on the Mac, that fires a key combo, launches an app, opens a URL, runs a Shortcut, or (opt-in) runs a script. |
| **SF Symbol** | Apple's system icon set; used for macro icons. |
| **ProMotion** | Apple displays with up to 120 Hz refresh and touch sampling. |
| **AP isolation** | Router/Wi-Fi setting preventing clients from talking to each other. |
| **TTFCM** | Time to first cursor move — primary onboarding metric. |
| **PPPC profile** | Privacy Preferences Policy Control MDM profile that pre-grants Accessibility on managed Macs. |
