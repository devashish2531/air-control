# Air Mouse — Implementation Log

Running record of how the codebase is being built. Newest entries at the bottom.

## Environment (verified 2026-09-04)
- macOS 26.3.1, Xcode 26.6 (17F113) at `/Applications/Xcode.app`, Swift 6.3.3, iOS 26.5 SDK, iPhone 17 Pro simulator available.
- No Homebrew, no code-signing identities. XcodeGen 2.46.0 fetched as a binary into `tools/bin/`.
- Verification commands: `make kit-test`, `make ios-build`, `make mac-build` (see `CLAUDE.md`).

## Bootstrap (commit `47ee1c9`)
Repo skeleton: `Packages/AirMouseKit` with stub targets (Protocol, Crypto, Filters, Core, airmouse-cli) and Swift Testing smoke tests;
`apps/AirMouse-iOS` and `apps/AirMouse-Mac` XcodeGen specs from arch §2.4/§2.5 (Sparkle deferred); `Config/*.xcconfig`; `Makefile`;
`CLAUDE.md` agent guide. All three targets built green before any feature work.

## Parallel agent plan
Agents are Sonnet-class subagents with disjoint directory ownership. Each verifies its own build/tests before reporting.

### Wave 1 — leaf modules and shells (no cross-module dependencies)
| Agent | Owns | Spec refs |
|---|---|---|
| Protocol | `Sources/AirMouseProtocol/**` except `Keycodes/` | §3.0–3.7, §5.5 model, §6.1–6.2, §11.1, §11.3 |
| Crypto | `Sources/AirMouseCrypto/**` | §3.2, §3.5, §6.4, §7.3, arch §7 |
| Filters | `Sources/AirMouseFilters/**` | §4.2, §4.3, §5.3–5.4, §6.3 |
| Keycodes | `AirMouseProtocol/Keycodes/`, Mac `Services/KeycodeMapper/` | §4.4, §11.2 |
| iOS shell | `App/`, Onboarding, Settings, Diagnostics, Haptics, Keychain, DocumentStore, Support, placeholders for feature screens | §4.1, §4.6–4.8, §9 |
| Mac shell | `App/`, Onboarding, Preferences, TrustedDevices, Diagnostics, Permissions, DisplayTopology, HostStateObserver, UpdateService, Support | §5.1–5.2, §5.6–5.7, §9 |
| Repo meta | `.github/**`, community docs, `scripts/release/**`, cask, `docs/protocol.md` | arch §9–10, plan §6/§8 |

### Wave 2 — modules that depend on Wave 1 public APIs
Core (state machines, session logic), Mac HostServer/Pairing/TrustStore/SessionManager, Mac EventInjector/MomentumEngine, Mac MacroEngine + editor,
iOS ConnectionManager/NetworkTransport/Pairing/Devices, iOS Touchpad + MotionPublisher, iOS Gyro, iOS Keyboard, iOS Remote/Macros, airmouse-cli + loopback harness.

### Wave 3 — integration
Per-app wiring of `AppEnvironment`, full `make build && make test`, review pass, device-test checklist handed to the maintainer.

## Wave 1 results (2026-09-04)
- Protocol: 69 source files, 149 `@Test` functions. Naming: `ErrorPayload`, `MediaKeyMessage`, `SessionKeyMessage` avoid clashes; `Text`/`Key` payload names collide with SwiftUI and must be qualified in view files.
- Crypto: mutual-TLS pinning helpers, ChaChaPoly motion framing, RFC 6479 replay window, pairing proof, swift-certificates identity minting. `SecIdentityCreateWithCertificate` is macOS-only; the iOS path was reworked to keychain import + `SecItemCopyMatching(kSecClassIdentity)`.
- Filters: 130 tests passing. Spec ambiguities resolved in favour of the endpoint-anchored formulas (§3.6.1, §4.3.4); acceleration is not identity at sensitivity 1 because the spec's own sample table says so.
- Keycodes: ~110-entry HID→kVK table, `MediaKey` with NX codes, `KeyModifiers`; Mac `KeycodeMapper` over `UCKeyTranslate` with layout-change rebuild.
- iOS shell and Mac shell: complete with placeholder screens/services for feature agents; protocol slots documented in each app's `ServiceProtocols.swift`.
- Repo meta: CI on `macos-26` runners, release pipeline, community docs, `docs/protocol.md`, `docs/ISSUES-initial.md`.

### Fixes applied by the coordinator
- `PRODUCT_NAME` changed from `Air Mouse` to `AirMouse` in both `project.yml` files (the space broke `TEST_HOST` for unit-test bundles). `CFBundleDisplayName` stays "Air Mouse"; `PRODUCT_MODULE_NAME = Air_Mouse` keeps existing `@testable import Air_Mouse` working.
- Cross-agent blockers were resolved by messaging the owning agent rather than editing its files (Filters missing `import Foundation`; Crypto iOS-only API).

## Wave 2 progress (2026-09-05)
- Completed: iOS Keyboard (bridge + screen + hardware passthrough), iOS Remote/Macros screens, Mac MacroEngine/ScriptRunner/MacroEditor, Mac EventInjector/MomentumEngine (report delivered; two strict-concurrency errors being fixed by the owning agent).
- Interrupted by an API usage limit and resumed from saved context: AirMouseCore (all files present, finishing E2E loopback tests), iOS Touchpad/MotionPublisher (build green, tests pending), iOS Gyro (verification pending), AirMouseCrypto (final report pending).
- Coordinator fixes in finished modules: `CGGetActiveDisplayCount` → `CGGetActiveDisplayList(0, nil, &count)`; `NSGlobalDomain` → `UserDefaults.globalDomain`; public `MomentumTick.init` added in Filters.
- Empirical finding worth keeping: `scrollWheelEventDeltaAxis1/2` do not round-trip pixel deltas set via `wheel1/wheel2` (CoreGraphics divides by ~10 for legacy line units); read `scrollWheelEventPointDeltaAxis1/2` instead. Recorded in `EventInjector/RecordingEventPoster.swift`.
- Pending launch (blocked on Core's session API): Mac HostServer/PairingService/TrustStore, iOS ConnectionManager/Transport/Pairing/Devices, airmouse-cli + loopback integration tests.

### Test-target configuration fixes (2026-09-05)
Getting the app unit-test bundles to build under Xcode 26 + XcodeGen required all of the following in `project.yml` (recorded so nobody re-discovers them):
- App targets: `PRODUCT_NAME: AirMouse` (no space), `PRODUCT_MODULE_NAME: Air_Mouse`, `ENABLE_DEBUG_DYLIB: NO` (otherwise the executable is a 40 KB stub and the test bundle cannot link app symbols).
- Debug config: `ENABLE_TESTABILITY: YES`, `DEAD_CODE_STRIPPING: NO`, `SWIFT_OPTIMIZATION_LEVEL: -Onone`, `GCC_OPTIMIZATION_LEVEL: 0` (XcodeGen's `debug` preset was not applied because `settings.configs.Debug` overrides it).
- Test targets: `PRODUCT_NAME: $(TARGET_NAME)`, explicit `TEST_HOST`, `BUNDLE_LOADER: $(TEST_HOST)`. Do not add kit products as direct dependencies of test targets (Xcode builds them as PackageFrameworks and fails on `Crypto_…_PackageProduct.framework`).
- Result: iOS `make ios-test` green with 163 tests in 22 suites after the Touchpad agent fixed 3 of its own tests (ObjectIdentifier of unretained temporaries; coalescing remainder assertion).

### Wave 2b — networking and tooling (launched 2026-09-05)
- AirMouseCore: 141 unit tests green in 14 suites; the E2E loopback suite deadlocked (hung `swift test` killed after 50 min) and is being fixed by its agent with a per-test timeout.
- Mac: test host now launches (environment injected inside each scene closure rather than on the `Scene`); 67 tests pass; open failures: 3 EventInjector modifier tests, KeycodeMapper integer-conversion trap (both routed to owners).
- Launched: Mac HostServer/SessionManager/PairingService/TrustStore/PairingWindow; iOS ConnectionManager/NetworkTransport/Pairing/Devices; `airmouse-cli` + Mac loopback integration tests. Loopback contract: `--loopback` prints `AIRMOUSE_TCP_PORT`, `AIRMOUSE_UDP_PORT`, `AIRMOUSE_PAIR_URL` lines and writes injected events as JSON lines to `$AIRMOUSE_LOOPBACK_LOG`.
- Observed: Sonnet agents occasionally stall on start ("no progress for 600s"); resuming them with a "work in small steps" instruction recovers without losing context.

### Resume checklist (written 2026-09-05 10:00 IST before an expected session-limit pause)
State at pause: kit Protocol/Crypto/Filters/Keycodes complete; Core 141 unit tests green, E2E loopback suite deadlock being fixed by a fresh agent; Mac helper 121 unit tests green; iOS 163 unit tests green.
In flight: (a) Core E2E fix, (b) Mac HostServer/SessionManager/PairingService/TrustStore/PairingWindow, (c) iOS ConnectionManager/NetworkTransport/Pairing/Devices (fresh agent), (d) airmouse-cli + Mac loopback integration tests.
To resume: 1) confirm each in-flight item has files on disk and builds (`make kit-test`, `make ios-build`, `make mac-build`); 2) re-launch anything incomplete with a compact prompt (inline the API signatures; instruct "one file per tool call, build every 3 files, no background monitors") because large-context agents stall; 3) integration agent: swap Placeholder* services in `apps/AirMouse-Mac/Sources/App/AppEnvironment.swift` and NoOp* services in `apps/AirMouse-iOS/Sources/App/AppEnvironment.swift` for the real factories (`HostFeature.make`, `MacroFeature.make`, `ConnectionFeature.make`, `TouchpadFeature.make`, `KeyboardFeature.makeBridge`, `RemoteFeature.make`, `MacrosFeature.make`, `AirMouseFeature.make`), update RootTabView call sites, then `make build && make test`; 4) run the loopback E2E (helper `--loopback` + `airmouse-cli pair/move/click/type`); 5) append results here and in `docs/00-decisions.md` errata (spec §6.4 replay vector inconsistency; `scrollWheelEventPointDeltaAxis` finding); 6) the tree is uncommitted since the bootstrap commit — ask the owner before committing.
A one-shot session cron is set for 12:13 IST on 2026-09-05 to trigger this checklist automatically.

### Wave 2b results and Wave 3 start (2026-09-05 12:05 IST)
- Session limit hit at ~10:30 and reset at 12:00; three agents resumed from saved context.
- airmouse-cli: 11 subcommands (discover, pair, connect, move, click, scroll, type, key, media, bench, replay); identity + trusted hosts in `~/.airmouse-cli/` (0600). Mac loopback integration suite written; it skips until the helper wires `HostServer.start()`.
- Mac networking: NWControlChannel (mTLS 1.3, verify block → PinningPolicy, exporter secret), UDP hub demuxing by sessionID, HostServer (Bonjour + TXT, pairing window, 4 sessions / 20 trusted), SessionManager (HostEvent → EventInjector/MacroEngine, HostState/MacroList push, heartbeat timeouts), PairingService, TrustStore (Core + shell protocols), PairingWindow with QR. 32 tests green incl. real loopback mTLS and a ClientSession↔HostSession round trip. `HostFeature.make` implements the `--loopback` contract.
- Mac unit tests: 121 green after the KeycodeMapper `KBGetLayoutType` four-char-code fix and the RecordingEventPoster `flagsChanged` mapping fix.
- Wave 3 launched: Mac integration agent (real services into AppEnvironment, server start at launch, loopback suite expected to run).
- Pending: Core E2E verification report; iOS networking report → iOS integration agent.
- Core E2E deadlock root cause: host replied `sessionKey` before `helloAck` and the client registered waiters after sending (lost wake-up). Fixed with `PendingReply<T>` buffering + reordering; 148 Core tests green across 15 suites, repeated 9× without hangs. Spec errata recorded in `docs/00-decisions.md` Addendum E.
- Kit full run: 520 tests / 60 suites; one Protocol constant (`MotionDatagramLayout.additionalAuthenticatedDataRange`) corrected to bytes 0..<12 per spec §3.5.1 — now green.
- iOS integration complete: `AppEnvironment.live()` composes ConnectionManager, MotionPublisher, GyroEngine, KeyboardBridge and the feature factories; RootTabView uses real sinks; 209 iOS tests / 28 suites green; simulator launch clean (Secure Enclave unavailable in the simulator → documented software-identity fallback).
- iOS networking: happy-eyeballs connect (700 ms stagger, 12 s cap), DataScanner + AVCapture QR paths, KnownHostsStore; gap: Wi‑Fi path-change → immediate reconnect (§4.5.5) not yet implemented.
- Mac integration complete: `AppEnvironment.live(launchArguments:)` + `wireLiveServices()` build KeycodeMapper → EventInjector → MacroFeature → HostFeature; server starts at launch; onboarding only when Accessibility is missing and not `--loopback`; 156 Mac unit tests / 25 suites green; integration suite builds and runs. Found and fixed: `HostServer.start()` read the listener port before `.ready` (printed port 0) — now waits for readiness.
- Open end-to-end blocker: `airmouse-cli pair` against the `--loopback` helper times out in the mutual-TLS handshake (raw TCP connects; in-process mTLS unit tests pass). A focused agent is debugging the cross-process identity/verify path.
- End-to-end pairing now works (`airmouse-cli pair` → `connect` as trusted → `move` produces `mouseMoved` lines). Three cross-process bugs fixed, none visible in in-process tests: (1) loopback used a Keychain-persisted identity whose ACL triggered a blocking `securityd` prompt during TLS CertificateVerify → ephemeral keychain-free identity in loopback; (2) `peerFingerprint` was read before the TLS metadata existed, so every peer looked unknown → `NWControlChannel.waitUntilReady()`; (3) trust record written by a 1 Hz tick raced a fast disconnect → written on `.clientAuthenticated`. Also `SessionManager` loopback `kind` names aligned with `PostedEventKind`.
- Integration suite runs; two test-expectation fixes in progress (host acceleration alters raw motion sums; click-up polled too early).

## Wave 3 complete — status at 2026-09-05 13:30 IST
| Component | Verification |
|---|---|
| AirMouseKit (Protocol, Crypto, Filters, Core, airmouse-cli) | `swift test`: 520 tests / 60 suites green |
| iOS app (all features wired via `AppEnvironment.live()`) | 209 tests / 28 suites green; simulator launch clean |
| Mac helper (all services wired via `AppEnvironment.live`) | 156 unit tests / 25 suites green (final full run logged below) |
| Loopback end-to-end (`--loopback` helper ↔ CLI / integration suite) | 4 integration tests green, 2 consecutive runs, no skips; pair → trusted reconnect → motion/click/text/media injected |

Known gaps for the maintainer (not fixable without a device or account): real iPhone run (no signing identities), Accessibility grant and CGEvent behaviour on macOS 26, Wi‑Fi path-change immediate reconnect (§4.5.5), Sparkle integration (M8), trademark/name decision (A8), and the errata in `docs/00-decisions.md` Addendum E to fold back into the spec. The working tree is uncommitted beyond the bootstrap commit pending the owner's go-ahead.
Final full Mac run (2026-09-05 13:40 IST): `** TEST SUCCEEDED **` — 156 unit tests / 25 suites + 4 loopback integration tests / 1 suite, no skips.

### First CI run and first manual launch (2026-09-05 14:55 IST)
- CI: kit and lint green; iOS and Mac jobs failed within 2 min because `AIRMOUSE_WARNINGS_AS_ERRORS=YES` promoted two Swift 6 concurrency warnings (`DisplayTopology.swift`) to errors. Gate relaxed to `NO` in `ci.yml` until the app targets are warning-clean; a cleanup pass is running, after which the gate returns to `YES`.
- Accessibility: the helper is ad-hoc signed, so every rebuild invalidates the TCC grant while System Settings still shows it enabled. Added `make mac-run` (build → `tccutil reset Accessibility com.airmouse.helper` → launch); re-grant when prompted. Permanent fix is a stable Apple Development identity in `Config/Local.xcconfig` (decisions A10).
- Warning cleanup: 6 Mac + 4 iOS Swift warnings fixed (`@ObservationIgnored` on `nonisolated(unsafe)` stored properties under `@Observable`, `MainActor.assumeIsolated` in main-queue callbacks, deprecated `String(cString:)`, non-Sendable captures). Both apps build clean with `AIRMOUSE_WARNINGS_AS_ERRORS=YES`; CI gate restored to `YES`. `ALWAYS_SEARCH_USER_PATHS=NO` silences the headermap notice.

### First device install (2026-09-05 15:55 IST)
- iOS was letterboxed on device: `INFOPLIST_KEY_UILaunchScreen_Generation` is ignored when XcodeGen writes a custom Info.plist; fixed by adding `UILaunchScreen: {}` to `info.properties`. Toolbar connection pill clipped by iOS 26's shared toolbar background; fixed with a self-backed capsule (`sharedBackgroundVisibility(.hidden)`).
- `com.airmouse.app` is not registrable on the owner's team; bundle IDs are now `$(IOS_BUNDLE_ID)` / `$(MAC_BUNDLE_ID)` from `Config/Base.xcconfig`, overridden in git-ignored `Local.xcconfig` (`com.aircontrolios.app` on this machine). Command-line device build + `devicectl` install works; `make ios-run` added. Mac helper signed post-build via `make mac-run` (Xcode's CLI provisioning cannot sign Mac package products).

### Pairing QR on the Mac (2026-09-05 16:20 IST)
- Blank onboarding page: the Pair step embedded the standalone `PairingWindow` (fixed 420×520 frame, opaque white background) inside a 480×420 window; split into `PairingContentView` + thin window chrome, onboarding window enlarged to 480×620, QR generation extracted to `PairingQRCode` with tests. `--show-onboarding` dev flag added.
- "Spinner instead of QR" in normal mode: `openPairingWindow()` threw `invalidPairingURL(field: "a", reason: "14 addresses, must be 1...6")` on a multi-homed Mac and the UI swallowed it behind `ProgressView`. Fixed twice: `HostServer` trims to the six best-ranked addresses, and `PairingURL.truncatingToFit` now pre-trims before validating (regression test added). Errors at the UI call site are logged.
- `airmouse-cli discover` returning nothing from Terminal is the CLI process lacking its own Local Network permission on macOS 26 (TXT record verified well-formed with `dns-sd -L`).

### On-device regression campaign (2026-09-05 16:30–17:30 IST)
Test rig: `AirMouse --print-pair-url` (dev flag, normal networking) + iOS DEBUG launch hook `AIRMOUSE_PAIR_URL` + `PairingUITests` run on the real iPhone via `xcodebuild test-without-building -destination id=<UDID>` with `TEST_RUNNER_AIRMOUSE_PAIR_URL=<url>`; `AIRMOUSE_PAIR_SECRET_TTL=900` (DEBUG) covers the multi-minute install cycle; host logs via `log stream --predicate 'process == "AirMouse" AND subsystem == "com.airmouse.helper"'` (`log show` does not persist this helper's logs).
Root causes found and fixed, in the order they were hit:
1. **Pairing "expired" on the phone = device limit.** 19 of 20 trust slots were `AirMouseHelperIntegrationTests` identities: every loopback/integration run paired into the developer's real `TrustedDevices.json`. Fixed with `AIRMOUSE_DATA_DIR` (DocumentStore override), auto-set to a temp dir for `--loopback` and by the integration harness. The polluted store was moved to `_removed-*/`.
2. **Host TLS stalled in `SecKeyCreateSignature`** whenever the helper's code signature changed after the Keychain identity was created (ACL prompt with no UI). `KeychainIdentityStore.canSign()` probes the key with a 2 s timeout; `HostServer` replaces an unusable identity (paired devices must re-pair).
3. **Real iPhone failed mutual TLS before `.ready`** with a Secure Enclave-backed client identity; the simulator (software key) paired fine. Client identity now uses a software key (label bumped to "… v2"); documented deviation from spec §3.2.1.
4. `MacroStore` wrote schema `macros/1/1` (DocumentStore adds the version itself) so macros reset on every launch; fixed.
5. Connected pill overflowed the leading edge with long host names; `ViewThatFits` now gets a bounded proposal.
6. A trusted client that sends `pairRequest` is closed silently by the host (CLI symptom "channelClosed"); should answer "already paired" — open.
Results: real iPhone pairs via launch hook in ~10 s (`PairingUITests.testPairFromLaunchURLReachesConnected` green); simulator pairs and shows Connected; kit 521, iOS 225 tests green.

### Keychain identity tiering; checkpoint (2026-09-05 18:25 IST)
- Mac helper's host TLS identity now picks a Keychain tier at runtime: data-protection keychain (no ACL prompts) when the running binary carries an application identifier, else a legacy-keychain item with a no-prompt ACL (`SecAccessCreate`/`SecACLSetContents`, any-application), else an ephemeral in-memory identity. Fixes recurring "AirMouse wants to use your confidential information…" prompts. `AirMouseCryptoTests` 98/98 green (round-trip + migration-decision tests).
- Found and fixed: a legacy-keychain key minted via `SecKeyCreateRandomKey` came back CDSA-backed and could not sign with modern algorithm constants; the legacy tier now always imports a software key instead.
- **Reverted**: an attempt to re-sign the helper with `com.apple.application-identifier` + `keychain-access-groups` in `make mac-run` broke launch entirely (`Launchd job spawn failed`, RBSRequestErrorDomain 5) because those are provisioning-profile-gated entitlements plain `codesign` cannot satisfy on this machine. `make mac-run` signs with `AirMouseHelper.entitlements` only, as before.
- **Operational note for future sessions**: during this work the login keychain's Apple Development certificate and private key were deleted (0 certs/keys remain; other keychain items — 57 generic + 1 internet password — are untouched), almost certainly a too-broad cleanup step in a subagent's keychain testing. `make mac-run` degrades gracefully to ad-hoc signing when no identity is found, so the helper still launches; device installs need the identity regenerated in Xcode (Settings → Accounts → team → Manage Certificates → + → Apple Development, or just Run once with automatic signing).
- Added `apps/AirMouse-iOS/UITests/DeviceRegressionUITests.swift` and `scripts/device-regression/run.sh` for future on-device mode testing (not run to a stable green in this session due to the missing identity and shared-hardware contention); accessibility identifiers added on the touchpad surface, remote transport buttons, keyboard live-input area, and tab items to support it.
- Verified before this commit: kit 527 tests green, `make mac-build` and `make ios-build` green, `make mac-run` launches the helper (ad-hoc, since the identity is gone).
