# Initial GitHub issues (ready to paste)

The first 10 issues from [`docs/05-plan.md`](05-plan.md) §8.2, formatted as `gh issue create`
commands. Run these once the repository exists on GitHub and the milestones from §8.1's
bootstrap runbook have been created (`M0 Bootstrap` … `M9 Release`). Replace `OWNER/air-control`
if you're not running these from inside a checked-out clone with `gh` already pointed at the
right repo (in that case you can drop `--repo OWNER/air-control` entirely and `gh` will infer it).

Labels referenced below (`infra`, `security`, `spike`, `critical-path`, `mac`, `ios`,
`performance`, `kit`, `testing`, `good first issue`) should exist in the repo already, or create
them first with `gh label create <name>` (a fresh repo only ships GitHub's defaults).

```bash
gh issue create --repo OWNER/air-control \
  --title "M0: CI workflow ci.yml green on empty targets (kit / ios / mac / lint)" \
  --milestone "M0 Bootstrap" \
  --label "infra" \
  --body "$(cat <<'EOF'
## Goal
Get `.github/workflows/ci.yml` passing end-to-end on the empty/placeholder targets created
during repo bootstrap (arch §9.1, plan §8.1) — before any real feature code exists.

## Acceptance
- [ ] `kit` job: `swift build` + `swift test` succeed in `Packages/AirControlKit` (even with only
      placeholder sources/tests).
- [ ] `ios` job: XcodeGen generates `apps/AirControl-iOS/AirControl.xcodeproj` and
      `xcodebuild test` succeeds against a simulator, `CODE_SIGNING_ALLOWED=NO`.
- [ ] `mac` job: XcodeGen generates `apps/AirControl-Mac/AirControlHelper.xcodeproj` and
      `xcodebuild test` succeeds, ad-hoc signed.
- [ ] `lint` job runs (SwiftLint, SwiftFormat --lint, `check-xcstrings.sh`) — non-blocking is
      fine for now (see arch §9.1 / plan §6).

## References
- docs/04-architecture.md §9.1
- docs/05-plan.md §8.1
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M0: SwiftLint custom rules — ban event taps, print, sleep; secret-interpolation check" \
  --milestone "M0 Bootstrap" \
  --label "infra,security" \
  --body "$(cat <<'EOF'
## Goal
Add custom SwiftLint rules to `.swiftlint.yml` that catch security-relevant footguns before
review, per the project's "no event taps, no raw CGEvent outside the injector" rule (spec §7.1
T1/T2, CLAUDE.md logging rule).

## Acceptance
- [ ] A custom rule (regex or `analyzer_rules`) flags `CGEvent.tapCreate`/`CGEvent.tapEnable`
      anywhere outside the one sanctioned injector path.
- [ ] A custom rule flags `print(` in app/kit sources (os.Logger only, per CLAUDE.md).
- [ ] A custom rule flags `sleep(` / `Thread.sleep` outside test targets.
- [ ] A custom rule flags string interpolation of anything named like `secret`, `proof`, `key`,
      `token` directly into a logging call (best-effort regex; false positives are fine to
      silence with an inline disable comment).
- [ ] Rules documented with a comment in `.swiftlint.yml` explaining why each exists.

## References
- docs/03-specifications.md §7.4 (logging and privacy)
- CLAUDE.md "Conventions"
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M1: Spike R-1 — SecIdentity from swift-certificates + SecKey on macOS and iOS (Path A/B)" \
  --milestone "M1 Spikes" \
  --label "spike,security,critical-path" \
  --body "$(cat <<'EOF'
## Goal
De-risk the identity/certificate path the whole pairing handshake depends on (spec §3.2.1):
build a self-signed P-256 X.509 leaf with `swift-certificates`, get it into a `SecIdentity`
usable by `Network.framework`'s TLS options, on both a Mac (login Keychain) and an iPhone
(Secure Enclave when available, else Keychain).

## Acceptance
- [ ] A throwaway executable/test proves Path A (Mac: `SecKeyCreateRandomKey` + Keychain) works
      end-to-end into `sec_protocol_options_set_local_identity`.
- [ ] A throwaway executable/test proves Path B (iOS: Secure Enclave key, else Keychain) works
      the same way.
- [ ] Findings (what worked, what didn't, any Apple API gotchas) written up in
      `docs/02-technical-research.md` or a follow-up doc, per plan's spike process.
- [ ] Unblocks M2/M3 identity code in `AirControlCrypto`.

## References
- docs/03-specifications.md §3.2.1
- docs/00-decisions.md Addendum A1
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M1: Spike R-1c — TLS exporter sec_protocol_metadata_create_secret availability" \
  --milestone "M1 Spikes" \
  --label "spike,security" \
  --body "$(cat <<'EOF'
## Goal
Confirm whether `sec_protocol_metadata_create_secret` (the TLS 1.3 exporter used to bind the
pairing proof to the live TLS session, spec §3.2.3) is actually available and behaves as
documented on both current iOS and macOS.

## Acceptance
- [ ] A minimal TLS 1.3 connection between two `Network.framework` endpoints successfully
      calls the exporter API on both sides and produces matching 32-byte secrets for matching
      label/context.
- [ ] If unavailable or unreliable: document the fallback path (32 zero bytes + advertise
      `"pair-binding-certs"`, spec §3.2.3) as the one that will actually ship, and file a
      follow-up issue to remove the fallback later if Apple fixes it.
- [ ] Result written up in `docs/02-technical-research.md` or a follow-up doc.

## References
- docs/03-specifications.md §3.2.3
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M1: Spike R-2 — synthesized-event acceptance matrix on macOS 26.3.1" \
  --milestone "M1 Spikes" \
  --label "spike,mac" \
  --body "$(cat <<'EOF'
## Goal
Verify which apps/contexts accept `CGEvent`-posted mouse/keyboard input under Accessibility-only
permission (no Input Monitoring, no event taps — decisions Addendum A5) on the actual target
macOS version, before building `EventInjector` against unverified assumptions.

## Acceptance
- [ ] A test matrix covering: Finder, a sandboxed app, a game/full-screen app, Mission
      Control gestures, and at least one Electron app — each row records whether pointer
      move/click/scroll and keyboard tap/hold were accepted.
- [ ] Any surprises (an app or context that silently drops synthesized events) documented with
      the exact `CGEventSourceStateID`/flags combination that was tried.
- [ ] Findings feed directly into `EventInjector` design in `docs/04-architecture.md` if they
      change any assumption there.

## References
- docs/00-decisions.md Addendum A5
- docs/03-specifications.md §7.1 (T-series threat model, permission scope)
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M1: Spike R-7 — Local Network prompt behaviour on iOS 18.6/26 and macOS 15/26" \
  --milestone "M1 Spikes" \
  --label "spike,ios,mac" \
  --body "$(cat <<'EOF'
## Goal
Confirm exactly when/how the iOS "Local Network" permission prompt fires relative to Bonjour
browsing and TCP connection attempts, across the OS versions this project targets, so onboarding
(FR-DP-002/003, AM-DP-02 timing target) doesn't get blocked on an unexpected prompt sequence.

## Acceptance
- [ ] Documented trigger point for the Local Network prompt on iOS 18.6 and iOS 26.
- [ ] Confirmed whether `NSLocalNetworkUsageDescription` + `NSBonjourServices` alone is
      sufficient, or whether an actual connection attempt is what triggers it.
- [ ] Confirmed the Mac side has no equivalent prompt for Bonjour registration on macOS 15/26.
- [ ] Findings feed into the onboarding flow spec / `Features/Onboarding` implementation.

## References
- docs/03-specifications.md §3.1.1
- docs/01-requirements.md (AM-DP-02, FR-DP-002/003)
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M1: Spike R-4 — UDP echo latency baseline with DispatchSerialQueue(.userInteractive) executors" \
  --milestone "M1 Spikes" \
  --label "spike,performance" \
  --body "$(cat <<'EOF'
## Goal
Establish a latency baseline for a bare UDP echo between an iPhone and a Mac on the reference
network setup (plan §6 performance gate: 120 Hz iPhone, Apple-silicon Mac, 5 GHz Wi-Fi 6, same
AP, no other traffic) using `DispatchSerialQueue(.userInteractive)` executors, before any
motion-pipeline code exists — so later regressions are measured against a real floor, not a
guess.

## Acceptance
- [ ] `aircontrol-cli`-style or standalone echo tool measures round-trip p50/p95/p99 over ≥ 1000
      samples.
- [ ] Baseline numbers recorded in `docs/perf/` (create the directory if it doesn't exist).
- [ ] Confirms or refutes that the p50 ≤ 12 ms / p95 ≤ 20 ms target (spec §8.1, plan §6) is
      achievable at the transport layer alone, before filters/crypto/injection overhead.

## References
- docs/05-plan.md §6 (performance gate)
- docs/03-specifications.md §8.1
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M2: FrameCodec + Envelope/Message Codable with round-trip and split-delivery tests" \
  --milestone "M2 Walking skeleton" \
  --label "kit,good first issue" \
  --body "$(cat <<'EOF'
## Goal
Implement `FrameCodec` (length-prefixed framing, spec §3.4.1) and `Envelope`/`Message` Codable
mapping (spec §3.4.2, §3.4.5) in `AirControlProtocol`.

## Acceptance
- [ ] `FrameCodec.encode(kind:body:) -> Data` and a `Decoder` that retains partial input up to
      256 KiB + 5 bytes, throwing `.frameTooLarge` beyond that.
- [ ] `Decoder.feed(_:) -> [Frame]` correctly handles a message split across multiple `feed`
      calls (partial length prefix, partial body) — test this explicitly.
- [ ] Every `Message` case round-trips through JSON encode → decode with `[.sortedKeys,
      .withoutEscapingSlashes]` per spec §3.4.3.
- [ ] Unknown `t` decodes without throwing (counted, not fatal); missing required fields throws
      a typed error.
- [ ] Tests in `AirControlProtocolTests` per spec §10.1 matrix.

## Test file to create
`Packages/AirControlKit/Tests/AirControlProtocolTests/FrameCodecTests.swift` and
`.../MessageCodableTests.swift`

## References
- docs/03-specifications.md §3.4
- docs/protocol.md §5 (condensed version)
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M2: QRPayload and TXTRecordModel parse/format with the §6.4 vectors" \
  --milestone "M2 Walking skeleton" \
  --label "kit,good first issue" \
  --body "$(cat <<'EOF'
## Goal
Implement `QRPayload` (parse/format `aircontrol://pair?...`) and `TXTRecordModel` in
`AirControlProtocol`, per spec §3.1.2–3.1.3.

## Acceptance
- [ ] Canonical URL ↔ struct round trip (the §6.4 vector).
- [ ] Malformed cases rejected with a typed error: missing `s`, URL > 512 bytes, IPv6 address
      with brackets (grammar requires no brackets), unknown `v`.
- [ ] `TXTRecordModel` encodes/decodes all seven keys (`v n id fp m tp up`) and enforces the
      ≤ 255 bytes/key, ≤ 400 bytes total limits.
- [ ] Tests in `AirControlProtocolTests` regenerate/verify against
      `Tests/AirControlProtocolTests/Vectors/qr.json` (generated by `scripts/gen-vectors.swift`).

## Test file to create
`Packages/AirControlKit/Tests/AirControlProtocolTests/QRPayloadTests.swift` and
`.../TXTRecordModelTests.swift`

## References
- docs/03-specifications.md §3.1.2–3.1.3, §6.4
- docs/protocol.md §2
EOF
)"

gh issue create --repo OWNER/air-control \
  --title "M2: --loopback mode + RecordingInjector + first integration test" \
  --milestone "M2 Walking skeleton" \
  --label "mac,testing,critical-path" \
  --body "$(cat <<'EOF'
## Goal
Build the `--loopback --port 0 --identity test [--pairing-secret <b64u>]` launch mode for
AirControlHelper and a `RecordingInjector` that logs would-be `CGEvent`s instead of posting them,
so contributors and CI can test the full session pipeline without a phone (arch §9.3, §10;
this is also what keeps `ci.yml`'s `mac` job secret-free).

## Acceptance
- [ ] Helper launched with `--loopback` uses an in-memory test identity (no Keychain writes) and
      exposes a local JSON control socket with the event log + counters.
- [ ] `RecordingInjector` conforms to whatever protocol `EventInjector` will implement, and
      records enough detail (button, keycode, deltas, click state) for assertions.
- [ ] First `AirControlHelperIntegrationTests` test: drives a real `NWConnection`-based client
      through pairing (`--pairing-secret`) and asserts the resulting recorded event(s) for one
      basic action (e.g. a single click).
- [ ] This test runs in the `mac` CI job without any secrets or Accessibility grant.

## Test file to create
`apps/AirControl-Mac/IntegrationTests/LoopbackIntegrationTests.swift` (extend the existing
placeholder if `apps/AirControl-Mac/IntegrationTests/LoopbackIntegrationTests.swift` already
exists from bootstrap)

## References
- docs/04-architecture.md §9.3, §10
- docs/03-specifications.md §3.2 (pairing), §3.4 (control channel)
EOF
)"
```
