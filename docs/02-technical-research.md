# Air Mouse — Technical Research & API Feasibility (2026-09-03)

Companion to `00-decisions.md`. Constraints assumed throughout: SwiftUI iPhone/iPad client (iOS 18+), Swift menu-bar helper (macOS 15+), local Wi-Fi, Bonjour discovery, QR pairing + TLS, CGEvent injection, < 20 ms motion latency, open-source direct distribution.

Confidence legend: **verified** = checked against Apple documentation / DTS forum answers / primary sources during this pass; **likely** = consistent with documentation and field experience but not re-verified end to end; **uncertain** = needs a spike.

Note on OS versions: the minimum is macOS 15 / iOS 18, but by the time v1 ships most users will be on macOS 26 (Tahoe) / iOS 26. Everything below must be tested on both.

---

## A. macOS event injection

### A1. Mouse move, click, drag — `CGEvent` (verified)

Use `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` and post to `.cghidEventTap` (the earliest tap location, so the event looks as much like hardware as possible). Create one `CGEventSource(stateID: .hidSystemState)` and reuse it.

```swift
let src = CGEventSource(stateID: .hidSystemState)
func move(to p: CGPoint, dx: Int, dy: Int, dragging: Bool) {
    let type: CGEventType = dragging ? .leftMouseDragged : .mouseMoved
    guard let e = CGEvent(mouseEventSource: src, mouseType: type,
                          mouseCursorPosition: p, mouseButton: .left) else { return }
    e.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
    e.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
    e.post(tap: .cghidEventTap)
}
```

Gotchas:
- **Drag needs `.leftMouseDragged`** (or `.rightMouseDragged` / `.otherMouseDragged`) while the button is held; `.mouseMoved` with a button down is ignored by many apps (Finder, drag-and-drop, window moves).
- **Click count**: set `.mouseEventClickState` to 2 on the second down/up pair of a double-click, and 3 for triple; keep the pairs within the user's double-click interval (`NSEvent.doubleClickInterval`). Without this, text selection by double-click does not work.
- Middle button: `.otherMouseDown` with `mouseButton: .center` and `.mouseEventButtonNumber = 2`.
- Do not `usleep` between down and up on the main thread; schedule the up on a `DispatchSourceTimer` (a few ms later) so the network thread never blocks.
- `hidSystemState` vs `combinedSessionState`: both work for posting; `hidSystemState` keeps synthesized modifier state consistent with the HID system so subsequent real keyboard input behaves. If real local input becomes sluggish right after a burst of synthesized events, set `CGEventSource.setLocalEventsFilterDuringSuppressionState(...)` to `.permitAllEvents`/`permitLocalMouseEvents` and `localEventsSuppressionInterval = 0` on the source (likely).

### A2. Scroll — `CGEvent(scrollWheelEvent2Source:units:wheelCount:wheel1:wheel2:wheel3:)` (verified API; phase behaviour likely)

`wheel1` = vertical, `wheel2` = horizontal, `wheel3` unused. `units: .pixel` gives trackpad-like smooth scrolling; `.line` behaves like a clicky mouse wheel (each unit scrolls ~3 lines, accelerated by the system). Use `.pixel` for two-finger scrolling and `.line` for "page/step" buttons.

To be treated as a trackpad (rubber-banding in Safari, elastic overscroll, momentum in `NSScrollView`), set the continuous/phase fields:

```swift
func scroll(dx: Int32, dy: Int32, phase: CGScrollPhase?, momentum: CGMomentumScrollPhase?) {
    guard let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2,
                          wheel1: dy, wheel2: dx, wheel3: 0) else { return }
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    if let p = phase    { e.setIntegerValueField(.scrollWheelEventScrollPhase,   value: Int64(p.rawValue)) }
    if let m = momentum { e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(m.rawValue)) }
    e.post(tap: .cghidEventTap)
}
```

Sequence: `.began` on first two-finger move, `.changed` per packet, `.ended` on lift, then — if velocity > threshold — a helper-side decaying series with `momentumPhase` `.begin`/`.continue`/`.end` at ~60 Hz (exponential decay, e.g. v *= 0.95 per tick until |v| < 0.5 px). The OS does not add momentum for you; the trackpad driver does that for hardware, so the helper must synthesize it. Emit momentum on the Mac, not the phone, so it survives packet loss and keeps working after the finger lifts.

Gotchas: apps read `scrollWheelEventPointDeltaAxis1/2` and `FixedPtDeltaAxis1/2` in addition to the integer deltas; the constructor fills these consistently when `.pixel` is used, so avoid overwriting only one. Whether the user's "natural scrolling" preference is applied to synthesized events posted at `.cghidEventTap` is **uncertain** — verify in the spike and, if not, apply `com.apple.swipescrolldirection` ourselves. Horizontal scroll works via `wheel2` with `wheelCount: 2`.

### A3. Keyboard — virtual keys and Unicode text (verified)

- Shortcuts / special keys: `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with Carbon `kVK_*` codes (`import Carbon.HIToolbox`). Set `event.flags = [.maskCommand, .maskShift]` on both the down and the up. Virtual keycodes are positional (ANSI layout); letters differ on non-US layouts, which is why text should not be typed via keycodes.
- Arbitrary text: a keyDown with `virtualKey: 0` plus `keyboardSetUnicodeString(stringLength:unicodeString:)`, then the matching keyUp. This types any Unicode regardless of the Mac's keyboard layout. Keep each event to a few UTF-16 units (chunk at ~20; longer strings are truncated by some apps) and pace chunks ~1 ms apart.

```swift
func type(_ s: String) {
    for chunk in s.utf16.chunked(into: 16) {       // small helper
        var units = Array(chunk)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
```

- Some apps (games, Electron shortcuts) only honour modifiers if they also see `.flagsChanged` events for the modifier key itself. For "hold ⌘" from the on-screen modifier keys, post `kVK_Command` down/up as key events with the flag set.
- Held-key repeat must be implemented by the helper (repeat timer using `NSEvent.keyRepeatDelay/keyRepeatInterval`).

### A4. Media keys — `NSEvent.otherEvent` system-defined subtype 8 (verified, long-standing but undocumented)

`CGEvent` virtual keys do not cover play/pause, volume, brightness. The standard technique posts an `NSEvent` of type `.systemDefined`, subtype 8, with `data1 = (keyType << 16) | (0xa00 keyDown / 0xb00 keyUp)`, using the `NX_KEYTYPE_*` constants from `IOKit/hidsystem/ev_keymap.h` (SOUND_UP 0, SOUND_DOWN 1, BRIGHTNESS_UP 2, BRIGHTNESS_DOWN 3, MUTE 7, PLAY 16, NEXT 17, PREVIOUS 18, FAST 19, REWIND 20).

```swift
func mediaKey(_ key: Int32) {
    for (flags, state) in [(0xa00, 0xa), (0xb00, 0xb)] {
        let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)), timestamp: 0,
            windowNumber: 0, context: nil, subtype: 8,
            data1: Int((Int(key) << 16) | (state << 8)), data2: -1)
        ev?.cgEvent?.post(tap: .cghidEventTap)
    }
}
```

Gotcha: it is private-ish behaviour (used by many open-source apps for 15+ years) and requires Accessibility like any other post. Volume can alternatively be set via `NSSound`/CoreAudio, but media transport has no public alternative, so keep this.

### A5. Multi-display coordinates (verified)

- `CGEvent` mouse positions are in the **global display space**: origin at the top-left of the main display, y increasing downward, spanning all displays as arranged. `CGDisplayBounds(id)` for each display from `CGGetActiveDisplayList` gives the rects in that space.
- `NSScreen.frame` / `NSEvent.mouseLocation` use the **AppKit space**: origin bottom-left of the main screen, y up. Convert with `cgY = NSScreen.screens[0].frame.height - nsY` (screens[0] is the one with the menu bar / origin).
- Keep the helper's own virtual cursor position (initialised from `CGEvent(source: nil)?.location`, which is already in CG space). Per motion packet: `p += delta`, then clamp: if the new point is inside any active display's bounds, accept; otherwise clamp to the current display (prevents the cursor vanishing into gaps in L-shaped arrangements). Re-read display list on `NSApplication.didChangeScreenParametersNotification`.
- Position drift: if a local mouse moves the cursor, the helper's virtual position is stale. Re-sync from `CGEvent(source: nil)?.location` at the start of each motion burst (no Input Monitoring needed to read the current location).

### A6. Relative delta vs cursor warping (verified for API; game behaviour likely)

Games, 3D apps, VNC clients, and anything that hides the cursor and calls `CGAssociateMouseAndMouseCursorPosition(false)` read `mouseEventDeltaX/Y` and ignore position. A `CGEvent` created with a position does **not** auto-populate deltas — always set them explicitly (as in A1). `CGWarpMouseCursorPosition` moves the cursor **without** generating an event and triggers the local-event suppression interval; do not use it. Limitation to document: apps that read raw HID via `IOHIDManager` (some games) never see synthesized CGEvents; the only fix is a DriverKit virtual HID device (Karabiner-DriverKit-VirtualHIDDevice approach) — out of scope for v1.

macOS 26 caveat (likely; single source): a 2026 write-up reports that on Tahoe WindowServer's `CGXSenderCanSynthesizeEvents()` dropped synthesized keyboard events from an *unsigned daemon* before they reached Carbon `RegisterEventHotKey` listeners. Our helper is a properly signed GUI app in the user session, which is the supported case, but "synthesized shortcuts trigger third-party global hotkeys on Tahoe" must be in the spike list.

### A7. Permissions: Accessibility vs Input Monitoring (verified)

TCC tracks three independent services: `kTCCServiceAccessibility`, `kTCCServicePostEvent`, `kTCCServiceListenEvent` (Input Monitoring).

- **Posting** CGEvents requires PostEvent, which System Settings displays under **Privacy & Security ▸ Accessibility**. `CGPreflightPostEventAccess()` / `CGRequestPostEventAccess()` are the precise APIs; `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true])` prompts for the same pane and is what most apps use.
- **Listening** (CGEventTap `.listenOnly`, `IOHIDManager`) requires Input Monitoring. Air Mouse never installs an event tap, so **Input Monitoring is not required**. Keep it that way; asking for both scares users.
- No permission is needed to *read* the cursor position or to post events to your own process.
- Prompting: call the request API from the onboarding screen, then deep-link with `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`. There is no change notification; poll `AXIsProcessTrusted()` at 1 Hz while the onboarding view is visible (the undocumented distributed notification `com.apple.accessibility.api` also fires; treat as optional).
- The `CFBundleExecutable` must be a real Mach-O (not a script) or TCC misattributes the grant (DTS-confirmed).

**Dev workflow / unsigned builds (verified by DTS threads + field reports):** TCC keys the grant to the app's code-signing designated requirement. Ad-hoc signatures have a designated requirement based on the CDHash, which changes on every build, so the Accessibility toggle stays "on" in System Settings but stops working after each rebuild (or the tap goes silently inert). Fix: sign every debug build with a **stable identity** — Xcode automatic signing with any Apple Development certificate (the free personal team works) yields a designated requirement of the form `identifier "com.airmouse.helper" and anchor apple generic and certificate leaf[subject.OU] = TEAMID`, which is stable across builds. Put `DEVELOPMENT_TEAM` in a git-ignored `Local.xcconfig` so each contributor uses their own team. When things get wedged: `tccutil reset Accessibility com.airmouse.helper`. Do not keep multiple copies of the helper around (DerivedData + /Applications); Launch Services picks one and the macOS 15 Local Network prompt is known to misbehave with duplicates.

### A8. Sandbox, hardened runtime, distribution (likely for sandbox; verified for notarization)

- Reports conflict on whether a sandboxed app can post CGEvents once Accessibility is granted: one 2025 blog asserts `CGEvent.post()` is "completely blocked inside App Sandbox"; on the other hand Mac App Store clipboard managers (e.g. Maccy, sandboxed) paste by posting ⌘V keyboard CGEvents after the user grants Accessibility. The decision (direct distribution, no sandbox) makes this moot; do not enable App Sandbox, and note in CONTRIBUTING that a Mac App Store build is not a goal.
- Direct distribution requires **Developer ID signing + hardened runtime + notarization** (`xcrun notarytool submit … --wait`, then `xcrun stapler staple`). CGEvent posting and Accessibility need no hardened-runtime exceptions. If the helper sends Apple Events (A9), add the `com.apple.security.automation.apple-events` entitlement and `NSAppleEventsUsageDescription`.
- Sparkle 2 runs fine in a non-sandboxed, hardened-runtime app with no extra entitlements; sign the framework with the same identity (Sparkle's `--deep` guidance) and use EdDSA appcast signatures.

### A9. Launching apps, Shortcuts, AppleScript (verified)

- Apps: `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` → `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)`. No permission needed. For the app-launcher grid, enumerate `/Applications` and read icons via `NSWorkspace.shared.icon(forFile:)`; sync bundle IDs + PNG icons to the phone.
- Shortcuts: run `/usr/bin/shortcuts run "Name"` via `Process` (no UI, no TCC beyond what the shortcut's actions need); `shortcuts list` gives the catalogue to sync. The `shortcuts://run-shortcut?name=` URL scheme works but foregrounds the Shortcuts app — avoid.
- AppleScript: `NSAppleScript` (compile once, execute on the main thread) or `OSAKit.OSAScript`. Scripts that target other apps trigger the per-target **Automation** prompt (`kTCCServiceAppleEvents`) on first use; the user can deny per app and there is no way to re-prompt except `tccutil reset AppleEvents`. Recommendation: v1 macros = key combos + app launch + Shortcuts; AppleScript as an "advanced" macro type behind a clear warning.

### A10. Menu bar app (verified)

`MenuBarExtra("Air Mouse", systemImage: "…") { … }.menuBarExtraStyle(.window)` (macOS 13+) for a popover-style panel that shows status, the QR code, and trusted devices. Set `LSUIElement = YES` so there is no Dock icon; add a `Settings` scene for preferences. Launch at login: `SMAppService.mainApp.register()` (macOS 13+); if `status == .requiresApproval`, call `SMAppService.openSystemSettingsLoginItems()`. Gotcha: `.window` style gives limited control over dismissal and has had focus quirks; if they bite, fall back to `NSStatusItem` + `NSPopover` hosting a SwiftUI view. Render the QR at high contrast in a dedicated window (not just the popover) so a phone camera can scan it from arm's length.

---

## B. Networking

### B1. Network.framework, Bonjour advertise/browse (verified)

Helper: `NWListener(using: tlsParams, on: .any)`, then `listener.service = NWListener.Service(name: hostName, type: "_airmouse._tcp", txtRecord: NWTXTRecord(["v": "1", "id": helperID]))`; observe `serviceRegistrationUpdateHandler` for the actual registered name. Phone: `NWBrowser(for: .bonjour(type: "_airmouse._tcp", domain: nil), using: params)`, and connect with `NWConnection(to: result.endpoint, using: params)` — Network.framework resolves the service endpoint for you, no separate resolve step. Set `parameters.includePeerToPeer = false`: peer-to-peer enables AWDL, whose channel hopping causes periodic 3–90 ms latency spikes on the LAN (verified 2025 research on AWDL stutter).

The new Swift-concurrency `NetworkConnection`/`NetworkListener`/`NetworkBrowser` APIs are **iOS 26 / macOS 26 only** (WWDC25), so with an iOS 18 / macOS 15 floor we stay on `NWConnection`. Wrap `NWConnection` in an `AsyncStream`-based actor so a later migration is mechanical.

### B2. TLS choice: PSK vs self-signed + pinning vs Noise (verified)

| Option | Status | Verdict |
|---|---|---|
| TLS-PSK via `sec_protocol_options_add_pre_shared_key` | **TLS 1.2 only** — Apple DTS confirms TLS 1.3 PSK is unsupported (rdar 53459020); TLS 1.3 attempts fail with `NO_SUPPORTED_VERSIONS_ENABLED` | Reject. Locks us to TLS 1.2, fragile, poorly documented |
| Self-signed identities + `sec_protocol_options_set_verify_block` pinning, mutual TLS 1.3 | Apple's recommended alternative; fully supported, hardware-accelerated, gets 1-RTT and session resumption for free | **Recommend** |
| Noise-style handshake with CryptoKit (X25519 + ChaChaPoly) over plain TCP/UDP | Full control, works over UDP, but hand-rolled protocol needs review and buys nothing on the LAN | Reject for v1 |

Design: each side generates a P-256 key at first launch (`SecKeyCreateRandomKey` in the keychain) and a self-signed X.509 certificate using `swift-certificates` (Security.framework has no public certificate-creation API; import the DER via `SecCertificateCreateWithData` + `SecItemAdd`, then `SecIdentityCopyPreferred`/query to obtain a `SecIdentity`). The QR encodes `{helperID, addresses[], port, SHA-256(helperCert), oneTimeToken(32 B), expiry}`. Pairing: phone connects with TLS 1.3, verify block compares `SecCertificateCopyData` hash to the pinned value, phone sends `HMAC(token, clientCertHash ‖ helperID)`; helper adds the client cert hash to its trusted list. Thereafter the helper requires client certs (`sec_protocol_options_set_peer_authentication_required(true)` + verify block against the trusted list) and the phone keeps pinning the helper cert. Set `sec_protocol_options_set_min_tls_protocol_version(.TLSv13)`.

```swift
let tls = NWProtocolTLS.Options()
sec_protocol_options_set_local_identity(tls.securityProtocolOptions, sec_identity_create(identity)!)
sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
    let sec = sec_trust_copy_ref(trust).takeRetainedValue()
    let leaf = (SecTrustCopyCertificateChain(sec) as? [SecCertificate])?.first
    complete(leaf.map { sha256(SecCertificateCopyData($0) as Data) == pinnedHash } ?? false)
}, .main)
```

Gotcha: building a `SecIdentity` from a freshly generated cert is the fiddliest part; prototype it first (see risks).

### B3. UDP for motion: DTLS vs application-layer ChaChaPoly (verified API; recommendation)

- `NWParameters(dtls: NWProtocolTLS.Options, udp: NWProtocolUDP.Options)` exists and gives DTLS over UDP. Field reports show DTLS is barely documented, version constants are confusing, and it is effectively DTLS 1.2 (uncertain). It also adds a handshake state machine on the lossy path and ~29 bytes/record overhead.
- Application-layer: after the TLS control channel is up, the helper sends a random 32-byte session key and a 4-byte session ID over TLS. Each datagram = `sessionID(4) ‖ counter(8) ‖ ChaChaPoly.seal(payload, key, nonce: counter-derived 12 B, authenticating: header)`. Receiver keeps a 64-bit sliding replay window (RFC 6479 style): drop if `seq ≤ highest − 64` or already seen. Overhead 4 + 8 + 16 tag = 28 bytes; 16-byte payload → 44-byte datagram. No handshake, tolerates loss and NAT rebinding, trivially unit-testable, and the session key can be rotated by the control channel.
- **Recommend application-layer ChaChaPoly.** Separate keys (or a direction byte in the nonce) for phone→Mac and Mac→phone. `sec_protocol_metadata_create_secret` (TLS exporter) could derive the key from the TLS session instead of sending it — nice-to-have, likely available, not required.

On iOS use `NWConnection(host:port:using: .udp)` (connected UDP; every `send` is one datagram). On the Mac, `NWListener(using: .udp)` yields one `NWConnection` per remote 5-tuple; index by session ID, not by tuple, so a phone changing ports keeps its session.

### B4. QUIC (verified API; assessment)

`NWProtocolQUIC` (iOS 15+/macOS 12+) supports datagrams: `NWProtocolQUIC.Options.isDatagram = true` marks a flow as a datagram flow, `maxDatagramFrameSize` configures RFC 9221 datagrams, and `NWProtocolQUIC.Metadata.usableDatagramFrameSize` reports the negotiated size. Streams and the datagram flow are created from an `NWMultiplexGroup`/`NWConnectionGroup` sharing one QUIC connection; ALPN is mandatory and TLS 1.3 certificate auth is required (PSK is not available, which is fine with B2's certificate design).

Assessment: attractive single-connection story (one handshake, streams for control, datagrams for motion, connection migration, 0-RTT reconnect) but the datagram flow is thinly documented, the API surface is more complex, and interop debugging (Wireshark) is harder. **Recommend TCP/TLS + encrypted UDP for v1; run a QUIC spike for v2.** Keep the transport behind a protocol so both can coexist.

### B5. iOS local network privacy (verified from TN3179, Feb 2026 revision)

- Info.plist: `NSLocalNetworkUsageDescription` and `NSBonjourServices = ["_airmouse._tcp", "_airmouse._udp"]`. Browsing a type not listed fails. The multicast entitlement is **not** needed for Bonjour (mDNSResponder does the multicast). Put the keys in the app's Info.plist, not an extension's.
- Requires access: outgoing TCP to a local address, sending/connecting UDP unicast, all Bonjour operations (register, browse, resolve), resolving `.local` names. Does **not** require access: listening/accepting incoming TCP, receiving incoming UDP unicast.
- Prompt timing: the alert appears on the first such operation, and "the system may deny the operation immediately, before the user has responded" — so retry after a short delay, and perform the first operation from the Connect screen, not at launch.
- Detecting denial (no general status API, FB8711182): `NWBrowser` → `.waiting(.dns(code))` with `code == kDNSServiceErr_PolicyDenied` (-65570); `NWConnection` → `.waiting` with `connection.currentPath?.unsatisfiedReason == .localNetworkDenied`. Offer a button to `UIApplication.openSettingsURLString`. To re-trigger the alert deliberately, TN3179's trick is to `connect()` a UDP socket to a link-local IPv6 address (no traffic generated).
- iOS 18.0–18.5 had a state-sync bug (FB14321888) that made the toggle not match behaviour; fixed in iOS 18.6 — recommend advising users to be on 18.6+.
- **macOS 15 also has the prompt.** Bonjour registration by the helper triggers it (launchd *agents* and GUI apps are not exempt; only daemons/root/Terminal children are). Add `NSLocalNetworkUsageDescription` to the helper too and handle `PolicyDenied` on the listener's registration — otherwise discovery silently fails while manual IP still works.

### B6. iOS background behaviour (verified)

When the app leaves the foreground the sockets are suspended within seconds; `NWConnection` reports `.waiting`/`.failed`. No background mode legitimately applies to a remote control (audio/location/VoIP hacks are App Review rejections). Use `beginBackgroundTask` for ~2 s to send a `pause` message (release held buttons and modifiers on the Mac — important, otherwise a stuck ⌘ key). Recommendation: foreground-only, `UIApplication.shared.isIdleTimerDisabled = true` while connected, on `scenePhase == .active` reconnect immediately (mTLS handshake ≈ 2 RTT ≈ 10–20 ms on the LAN) and reuse the UDP session key so motion resumes with no extra round trip. Show a Live Activity or Dynamic Island item? Not applicable (no background execution). Consider a lock-screen widget only as a launcher.

### B7. Hotspot, client isolation, mDNS reliability, manual fallback (likely)

- Personal Hotspot: the Mac joins the phone's hotspot; the phone is the gateway (172.20.10.1). Bonjour generally works over the hotspot interface but Apple's own QA notes device-to-device limitations; treat as best effort and rely on the QR address list.
- AP client isolation (hotel/guest/corporate Wi-Fi) blocks all client-to-client traffic; nothing works, including manual IP. Detect: TCP connect times out to every advertised address → show a "this network isolates devices; use Personal Hotspot" hint.
- mDNS is often filtered on enterprise Wi-Fi; unicast still works. Therefore the QR must embed **all** of the helper's IPv4/IPv6 addresses (`getifaddrs`, prefer `en0`) plus port and cert hash, so pairing never depends on Bonjour; the phone also caches the last-known addresses per helper. Reconnect order: last-known address → Bonjour result → QR list.
- Multipath TCP is irrelevant here (needs server-side support and is for WAN failover). Do not set `multipathServiceType`.
- Wi-Fi power save: an idle iPhone radio sleeps between DTIM beacons; the first packet after idle can take 50–200 ms. Keep a low-rate heartbeat (2 Hz idle, 30+ Hz while the trackpad is touched) so the radio stays awake during interaction. (Consistent with Moonlight/Steam Link field reports; not Apple-documented.)

### B8. Latency budget (verified numbers where cited; totals are estimates)

| Stage | Typical | Notes |
|---|---|---|
| Touch sampling wait | 4.2 ms avg (120 Hz), 8.3 ms (60 Hz) | iPhone touch scan is 120 Hz even on 60 Hz displays; ProMotion iPads sample 120 Hz (240 Hz Pencil) |
| UIKit touch delivery | 0–8 ms | Touches are delivered per display frame; coalesced touches recover samples but not latency |
| Gyro (motion mode) | 5 ms avg + ~1 ms | CoreMotion tops out at 100 Hz |
| Filter + encode + encrypt | < 0.3 ms | ChaChaPoly on 16 bytes is microseconds |
| Wi-Fi one-way, quiet 5/6 GHz LAN | 2–5 ms | Jitter 10–30 ms under contention; 50+ ms after radio sleep; AWDL bursts 3–90 ms |
| Mac receive + decrypt + `CGEvent.post` | < 0.5 ms | Post is synchronous IPC to WindowServer |
| Cursor shown at next display refresh | 8.3 ms avg (60 Hz), 4.2 ms (120 Hz Mac) | Cursor is a hardware overlay updated at vsync |
| **Total, median** | **≈ 15–20 ms** (120 Hz phone, 60 Hz Mac) | ≈ 11–13 ms with 120 Hz Mac; ≈ 25 ms with a 60 Hz phone |

The 20 ms target is achievable at the median on a good network with a ProMotion phone; the tail (p95/p99) is dominated by Wi-Fi jitter, which no client-side work fixes — so the design goal is "never add to it": one datagram per frame, no batching timers, no TCP for motion, no main-thread hops. Measurement plan: (1) RTT via echo datagrams every 100 ms, report p50/p95 in the UI; (2) ground truth with a 240 fps slo-mo video of finger and cursor; (3) `os_signpost` from receive to post on the Mac.

---

## C. iOS input

### C1. Touch (verified API; recommendation)

SwiftUI `DragGesture` is unsuitable: no per-touch identity, no multi-touch, no `coalescedTouches`/`predictedTouches`, and updates only once per frame. Use a `UIView` subclass inside `UIViewRepresentable` overriding `touchesBegan/Moved/Ended/Cancelled` with `isMultipleTouchEnabled = true`:

```swift
override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches {
        for c in event?.coalescedTouches(for: t) ?? [t] {
            let p = c.preciseLocation(in: self), q = c.precisePreviousLocation(in: self)
            engine.sample(id: ObjectIdentifier(t), dx: p.x - q.x, dy: p.y - q.y,
                          t: c.timestamp, radius: c.majorRadius)
        }
        if let pred = event?.predictedTouches(for: t)?.last { engine.predict(pred.preciseLocation(in: self)) }
    }
}
```

- Sum coalesced deltas per frame and send one datagram per frame (at 120 Hz that is the motion stream rate). Use `predictedTouches` sparingly (≤ 1 frame of extrapolation, blend 50 %) — it reduces perceived lag but overshoots on direction changes.
- Gesture state machine (deterministic, injected clock, unit-tested): tap = down→up < 250 ms and < 8 pt travel; two-finger tap = right click; two-finger move = scroll (send pixel deltas, phone-side no momentum — Mac does it); three-finger move = drag (button held, `.leftMouseDragged`); tap-and-hold 300 ms = drag lock; tap-then-drag ("tap-and-a-half") optional. Wait up to ~80 ms after the first finger lands before committing to a one- vs two-finger interpretation; count fingers by the maximum concurrent touches during the gesture.
- Palm rejection basics: ignore touches with `majorRadius` above a threshold, touches that begin within ~12 pt of screen edges, and any touch set with > 4 fingers; on iPad ignore `.pencil` type for the trackpad surface or treat as precise input.
- Run the gesture engine on the main thread (touch delivery) but hand packets to a dedicated `DispatchQueue(qos: .userInteractive)` for encryption and send.

### C2. Motion / gyro (verified API; mapping and filter are recommendations)

`CMMotionManager` with `deviceMotionUpdateInterval = 1/100` (100 Hz is the hardware/API ceiling) and `startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue)` on a `.userInteractive` `OperationQueue`. Use `deviceMotion.rotationRate` (bias-corrected by sensor fusion; better than raw `gyroData`) in rad/s. Because we map angular *rate* to cursor *delta*, there is no absolute heading to drift — residual bias appears as slow creep, which is what the clutch handles.

Gravity-aware mapping so the phone works both held flat (like a laser pointer) and upright (like a TV remote): yaw about the world vertical drives x; pitch about the device's horizontal axis drives y.

```swift
let g = simd_normalize(simd_double3(m.gravity.x, m.gravity.y, m.gravity.z))
let w = simd_double3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
let yawRate   = -simd_dot(w, g)                           // rotation about "up"
let deviceX   = simd_double3(1, 0, 0)
let horizX    = simd_normalize(deviceX - simd_dot(deviceX, g) * g) // device x, flattened
let pitchRate = -simd_dot(w, horizX)
var dx = yawRate * gainPxPerRad * dt, dy = pitchRate * gainPxPerRad * dt
```

Gain ≈ 800–1500 px/rad, with a dead zone (|rate| < 0.02 rad/s → 0) and an acceleration curve. **Drift/creep mitigation:** clutch button (move only while held — also solves "how do I click without moving"), double-tap clutch to recentre, auto-freeze when accelerometer variance says the phone is at rest. **Filter:** One-Euro filter (Casiez 2012): `minCutoff ≈ 1.0 Hz`, `beta ≈ 0.02`, `dCutoff = 1 Hz` — smooths jitter at low speed while staying responsive at high speed; expose the two knobs as "steadiness" and "responsiveness" sliders. Apply the filter to the rates before scaling. Send at 100 Hz as the same 16-byte motion packet as the trackpad.

### C3. Haptics (verified)

`UIImpactFeedbackGenerator(style: .rigid)` for click down, `.light` for up, call `prepare()` on touch-down so the actuator is ready (latency then < 10 ms); `UISelectionFeedbackGenerator` for scroll detents and modifier toggles. CoreHaptics (`CHHapticEngine`, transient events with sharpness/intensity) if left vs right click should feel distinct. Guard with `CHHapticEngine.capabilitiesForHardware().supportsHaptics` — most iPads have no Taptic Engine, so the trackpad must not depend on haptics for feedback (add a subtle visual pulse).

### C4. Keyboard input (verified API; IME handling likely)

- Soft keyboard: a hidden `UITextView` as first responder (not `UIKeyInput` alone — bare `UIKeyInput` breaks multi-stage IMEs such as Japanese/Chinese because there is no marked-text support). Configure `autocorrectionType = .no`, `spellCheckingType = .no`, `smartQuotesType/smartDashesType/smartInsertDeleteType = .no`, `textContentType = nil`. In `textViewDidChange`, if `markedTextRange != nil` do nothing (composition in progress); otherwise diff the buffer against the last sent state, emit `insertText` / `deleteBackward(n)`, and reset the buffer to a sentinel so backspace on an "empty" field still fires. `Return` → send Enter; `Tab`/arrows/Esc/⌘/⌥/⌃/fn keys via an `inputAccessoryView` toolbar with sticky modifiers.
- Hardware keyboard (iPad Magic Keyboard, Bluetooth): override `pressesBegan/pressesEnded` on the first-responder view; `press.key?.keyCode` is a `UIKeyboardHIDUsage` (USB HID usage) — build a HID-usage → macOS `kVK_*` table (both are finite; ~110 entries). Modifier keys arrive as their own presses (iOS 13.4+), so held ⌘/⌥ can be forwarded as `.flagsChanged`. To stop iPadOS from swallowing arrows and ⌘-combos, register `UIKeyCommand`s with `wantsPriorityOverSystemBehavior = true` (iOS 15+); ⌘Tab, ⌘H, ⌘Space and the Globe key still cannot be captured — document it.
- Bonus (likely): `GCMouse` (GameController, iOS 14+) exposes raw dx/dy from a trackpad/mouse attached to the iPad, so the Magic Keyboard trackpad can drive the Mac cursor directly. Worth a small spike.

### C5. QR scanning (verified)

`DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)` (VisionKit, iOS 16+). It requires an A12+ device (2018 or later) — check `DataScannerViewController.isSupported && .isAvailable` at runtime, not just `#available`. Fallback: `AVCaptureSession` + `AVCaptureMetadataOutput` with `metadataObjectTypes = [.qr]` (works everywhere). `NSCameraUsageDescription` required; handle `.denied` with a Settings deep link and a **manual entry fallback** (short numeric pairing code + IP shown under the QR). Encode the QR as `airmouse://pair?d=<base64url(binary payload)>` and register the scheme + a Universal Link so the iOS Camera app can open the app directly.

### C6. iPad (verified)

Layout from `horizontalSizeClass`/`verticalSizeClass` and the actual view size (Stage Manager and Split View resize windows arbitrarily — never branch on `userInterfaceIdiom` alone). `NavigationSplitView` for devices/settings; the control surface is a custom layout (landscape: trackpad + keyboard/modifier strip; portrait: trackpad above keyboard). Keep `UIRequiresFullScreen = false` so the app is a good multitasking citizen; the trackpad surface just shrinks. Hardware keyboard passthrough only while the scene is active. Prefer `.persistentSystemOverlays(.hidden)` and hide the home indicator on the trackpad screen; disable edge-swipe interference with `preferredScreenEdgesDeferringSystemGestures`.

---

## D. Shared code & project structure

### D1. Protocol package (recommendation)

`Packages/AirMouseProtocol` (SPM, platforms `.iOS(.v18), .macOS(.v15)`), depending only on Foundation + CryptoKit. Two wire formats:

- **Motion datagram**: hand-packed, fixed-size, little-endian, no Codable. Layout (16 bytes): `u8 type/version`, `u8 buttons bitmask`, `u16 seq`, `u32 timestampµs (monotonic, wraps)`, `i16 dx`, `i16 dy`, `i16 scrollX`, `i16 scrollY` — deltas in 1/8-pixel fixed point (±4096 px per packet). Encrypted frame = 28-byte header/tag + 16 = 44 bytes.
- **Control channel** (pairing, key exchange, clicks that must not be lost, keyboard text, macros sync, app list, clipboard): length-prefixed frames via `NWProtocolFramer` with a **JSON `Codable` envelope `{v, type, payload}`** in v1. Rates are < 100 msg/s, JSON is debuggable with `nc`/Wireshark, and there is no schema toolchain for contributors. Protobuf (`swift-protobuf`) only becomes worth it if non-Swift clients appear (Android, Windows helper); MessagePack saves bytes but not complexity. Encode timestamps and enums as ints; version every message.

### D2. Xcode layout (recommendation)

One `AirMouse.xcodeproj` with two app targets (`AirMouse` iOS, `AirMouseHelper` macOS) and local packages `Packages/AirMouseProtocol` and `Packages/AirMouseCore` (filters, gesture engine, pure Swift, testable with `swift test`). Use Xcode 16 **buildable folders** (file-system-synchronized groups) so `project.pbxproj` no longer changes when files are added — this removes most of the merge-conflict argument for XcodeGen/Tuist. Tuist/XcodeGen add a required tool for every contributor and hide settings behind a DSL; not worth it for two targets. Signing: `Config/Base.xcconfig` committed, `Config/Local.xcconfig` git-ignored with `DEVELOPMENT_TEAM`, bundle-ID suffix per developer to avoid TCC/Launch Services collisions.

### D3. Testing (recommendation)

- Unit (package level): codec round-trips and fuzzed decoding, replay window, One-Euro filter against golden vectors, gesture state machine with an injected clock, display clamping with multi-display fixtures, pairing HMAC/transcript.
- Integration: the helper abstracts injection behind `protocol EventInjector`; a `RecordingInjector` plus `--loopback` flag starts the listener on 127.0.0.1 with an ephemeral test identity. A macOS test target drives it with the real client transport and asserts on recorded events. CI runners have no Accessibility grant, so **no test may touch real `CGEvent`**.
- UI tests: onboarding smoke test only. Latency: a `--bench` mode that echoes datagrams and prints RTT percentiles.

### D4. CI (verified for secrets behaviour)

GitHub Actions on `macos-15`/`macos-26` runners with a pinned Xcode via `xcode-select`. PR workflow: `swift test` for packages, `xcodebuild build test` for the iOS target on a simulator with `CODE_SIGNING_ALLOWED=NO`, `xcodebuild build test` for the macOS target, SwiftLint + SwiftFormat `--lint`. Release workflow (on tag): import the Developer ID `.p12` into a temporary keychain, build/archive, `notarytool` with an App Store Connect API key (`--key`, `--key-id`, `--issuer`; the key needs only the Developer role), staple, build DMG, `generate_appcast` with the Sparkle EdDSA private key, upload to GitHub Releases, bump the Homebrew cask via PR.

Secrets in an open-source repo: `pull_request` runs from forks receive **no secrets**, so PR CI is safe by construction. Never use `pull_request_target` with a checkout of the PR head. Put all signing/notary/Sparkle secrets in a GitHub **Environment** ("release") with required reviewers and a deployment-branch rule (tags + `main` only); set `permissions: contents: write` only on the release job. Rotate the ASC key if a maintainer leaves.

### D5. Distribution (verified)

- iOS: App Store/TestFlight requires the maintainer's paid Apple Developer account; a public TestFlight link is the best beta channel. Contributors run from Xcode with a free personal team (7-day provisioning, 3 apps). AltStore/SideStore sideloading works from the released IPA (7-day refresh, needs AltServer on a computer) and alternative marketplaces in the EU — mention, do not support officially.
- macOS: notarized DMG/zip on GitHub Releases, `brew install --cask airmouse`, Sparkle 2 for in-app updates (appcast on GitHub Pages or Releases; EdDSA keys; HTTPS only — the Remote Mouse cleartext-update CVE is the cautionary tale).

---

## E. Prior art

| Product | Does well | Gets wrong | Lesson for Air Mouse |
|---|---|---|---|
| Remote Mouse (Emote) | Polished trackpad, media/app remotes, huge install base | Free tier ads + subscription; 2021 "MouseTrap" CVE-2021-27569…27574: unauthenticated UDP RCE, replay auth bypass, cleartext HTTP updater; vendor did not respond to disclosure (verified) | Authenticate **every** datagram, replay window, signed HTTPS updates, security contact + policy in repo |
| Mobile Mouse | Long-lived, low-latency reputation, per-app remotes, acceleration options | Paid/proprietary server; encryption story undocumented (uncertain) | Latency is a selling point users notice; offer acceleration/sensitivity presets |
| Unified Remote | 90+ remotes, cross-platform, extensible | Free with ads; CVE-2022-3229 auth-bypass RCE (no-password default) and 2023 CORS RCE on the localhost web admin (verified) | No optional-auth mode, no HTTP admin server on the Mac, deny-by-default pairing |
| KDE Connect / Valent | Open source, TLS with self-signed certs and pairing, plugin model, remote input | iOS client is limited; JSON over TCP is not trackpad-grade; discovery flaky on strict networks | Cert-pairing UX is proven and understood; motion needs UDP; ship manual-IP fallback |
| Barrier → Input Leap → Deskflow | KVM sharing across computers, mDNS discovery, active upstream (Deskflow; Barrier and Input Leap are dead forks, verified) | TLS optional/off by default historically; 2021 auth/DoS CVEs; not a phone input solution | TLS is not optional; a clear single maintained upstream matters for OSS trust |
| Apple iPhone Mirroring (macOS 15/iOS 18) | Seamless pairing via iCloud, excellent latency, zero setup | Opposite direction (Mac controls iPhone); requires same Apple ID | The bar for "it just works" pairing UX |
| Apple Universal Control | Share Mac keyboard/trackpad with iPad, instant, low latency | iPad only, same Apple ID, no iPhone as input, no motion pointer | Air Mouse's niche: iPhone as input, any account, presenter/motion modes |

---

## Key technical recommendations

1. Inject with `CGEvent` posted to `.cghidEventTap` from one `hidSystemState` source; always set `mouseEventDeltaX/Y`, never `CGWarpMouseCursorPosition`; use `*MouseDragged` while a button is held and set `mouseEventClickState` for multi-clicks.
2. Scroll with pixel units + `scrollWheelEventIsContinuous` and scroll/momentum phase fields; synthesize momentum on the Mac at ~60 Hz.
3. Type text with `keyboardSetUnicodeString` (layout-independent), shortcuts with `kVK_*` + flags, media keys via `NSEvent.otherEvent` subtype 8.
4. Request only Accessibility (PostEvent); never install an event tap so Input Monitoring is never asked for. Sign debug builds with a stable Apple Development identity via a git-ignored `Local.xcconfig` to stop TCC resets.
5. Direct distribution: Developer ID + hardened runtime + notarization; Sparkle 2 (EdDSA, HTTPS) + GitHub Releases + Homebrew cask. No App Sandbox.
6. Control channel: TCP with mutual TLS 1.3, self-signed P-256 identities (via `swift-certificates`), pinned by SHA-256 fingerprints exchanged during QR pairing. Do not use TLS-PSK (TLS 1.2 only on Apple platforms).
7. Motion channel: plain UDP, 16-byte fixed little-endian packets encrypted with CryptoKit ChaChaPoly under a per-session key delivered over TLS, 64-bit counter nonce and sliding replay window; one datagram per input frame, never batched.
8. QUIC datagrams exist in Network.framework but stay a v2 spike; keep transport behind a protocol.
9. Declare `NSLocalNetworkUsageDescription` + `NSBonjourServices` (`_airmouse._tcp`, `_airmouse._udp`) on **both** apps (macOS 15 prompts too); detect denial via `kDNSServiceErr_PolicyDenied` and `.localNetworkDenied`; trigger the prompt from the Connect screen and retry once.
10. Embed all helper IP addresses + port + cert hash + one-time token in the QR so pairing never depends on mDNS; cache last-known addresses; `includePeerToPeer = false`.
11. Foreground-only on iOS with `isIdleTimerDisabled`, a `pause` message on background (release held keys/buttons on the Mac), instant reconnect with the retained UDP session key; low-rate heartbeat to keep the Wi-Fi radio awake.
12. Touch via a UIKit view with `coalescedTouches` (and cautious `predictedTouches`) under SwiftUI; a deterministic, unit-tested gesture state machine; no SwiftUI `DragGesture` for the trackpad.
13. Motion via `CMDeviceMotion.rotationRate` at 100 Hz with gravity-aware yaw/pitch mapping, One-Euro filtering, dead zone, clutch button and auto-freeze at rest.
14. Keyboard via a hidden `UITextView` honouring marked text (IME-safe) and `pressesBegan` HID-usage → `kVK` mapping for hardware keyboards with `wantsPriorityOverSystemBehavior`.
15. Project: one `.xcodeproj` with Xcode 16 buildable folders, two app targets, two local SPM packages (`Protocol`, `Core`) tested with `swift test`; a `RecordingInjector` loopback mode so CI never needs Accessibility; release secrets only in a protected GitHub Environment.

## Risks needing a spike / prototype

1. **Self-signed `SecIdentity` creation** with `swift-certificates` + Security keychain on both platforms, and mutual-TLS verify/challenge blocks in Network.framework — the most fiddly security-critical piece; prototype before anything else.
2. **macOS 26 (Tahoe) synthesized-event acceptance**: confirm mouse, keyboard, shortcuts to third-party global hotkeys, and media keys all work from a signed GUI helper on 26.x, not only 15.x.
3. **Scroll fidelity**: confirm natural-scrolling inversion, phase/momentum handling in Safari, Xcode, Electron apps, and whether `.pixel` events are accelerated by the system.
4. **End-to-end latency measurement** on a 120 Hz iPhone → 60 Hz and 120 Hz Macs over typical home Wi-Fi with a 240 fps camera; validate the budget table and the heartbeat-vs-power-save hypothesis.
5. **Gesture disambiguation feel**: the ~80 ms two-finger wait and tap-vs-drag thresholds need hands-on tuning against Apple's trackpad.
6. **Motion mapping across grips** (flat vs upright) and One-Euro parameters; check creep after 5 minutes with clutch held.
7. **Local network prompt behaviour** on iOS 18.6+/26 and macOS 15/26 for both apps, including the "denied before the user answers" retry path and the helper's Bonjour registration under denial.
8. **Personal Hotspot and client-isolated networks**: does Bonjour work over the hotspot; does the manual-IP path recover; how to explain failure to the user.
9. **IME keyboard handling** with Japanese/Chinese/Korean keyboards through the hidden `UITextView` diffing approach.
10. **Hardware keyboard capture limits** on iPad (`wantsPriorityOverSystemBehavior`, which ⌘ combos are lost) and `GCMouse` for Magic Keyboard trackpad passthrough.
11. **QUIC datagram flow** in Network.framework as the v2 single-connection transport (API ergonomics, latency versus raw UDP).
12. **TCC stability of the dev loop**: verify the stable-identity workflow removes re-grant churn across Xcode rebuilds and app moves, and document `tccutil reset` steps for contributors.

## Sources consulted

- Apple TN3179 "Understanding local network privacy" (rev. Feb 2026) — https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- Apple Developer Forums: TLS 1.3 with PSK using Network framework (DTS: PSK is TLS 1.2 only) — https://developer.apple.com/forums/thread/688508
- Apple docs: `NWProtocolQUIC.Options` (`isDatagram`, `maxDatagramFrameSize`, iOS 15+/macOS 12+) — https://developer.apple.com/documentation/network/nwprotocolquic/options ; forum thread on QUIC datagrams — https://developer.apple.com/forums/thread/685976
- Apple Developer Forums: CGEventPost / TCC / native executable requirement (DTS) — https://developer.apple.com/forums/thread/724603 ; `CGRequestPostEventAccess` shown under Accessibility — https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess()
- Apple Developer Forums: DTLS options in Network.framework — https://developer.apple.com/forums/thread/124620 ; iOS 18 local-network status check — https://developer.apple.com/forums/thread/768139
- WWDC25 "Use structured concurrency with Network framework" (iOS 26 `NetworkConnection` APIs) — https://developer.apple.com/videos/play/wwdc2025/250/
- CGEvent taps and code-signing identity (2026) — https://danielraffel.me/til/2026/02/19/cgevent-taps-and-code-signing-the-silent-disable-race/ ; Tahoe synthesized hotkeys — https://www.nick-liu.com/posts/tahoe-hotkey-dead-end/ ; sandbox claim — https://www.quicopy.com/blog/macos-sandbox-keyboard-shortcuts
- Michael Tsai, "Local Network Privacy on Sequoia" — https://mjtsai.com/blog/2024/10/02/local-network-privacy-on-sequoia/
- Remote Mouse "MouseTrap" CVEs — https://thehackernews.com/2021/05/6-unpatched-flaws-disclosed-in-remote.html ; Unified Remote CVE-2022-3229 / 3.13.0 RCE — https://www.rapid7.com/db/modules/exploit/windows/misc/unified_remote_rce/ , https://www.exploit-db.com/exploits/51309
- Deskflow project status and forks — https://github.com/deskflow/deskflow/wiki/Project-Forks
- AWDL latency spikes research (The Register, Oct 2025) — https://www.theregister.com/2025/10/23/apple_airdrop_awdl_latency_research/
- DataScannerViewController device requirements (WWDC22 session 10025) — https://developer.apple.com/videos/play/wwdc2022/10025/
