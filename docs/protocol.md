# Air Mouse wire protocol (contributor reference)

This is a condensed, contributor-facing extraction of the wire protocol for anyone
implementing a client or host without reading the whole spec. **The normative source is
[`docs/03-specifications.md`](03-specifications.md) §3 (wire protocol) and §6 (shared package /
test vectors); if this document and the spec ever disagree, the spec wins** — file an issue to
get this page corrected. Byte layouts and message tables below are reproduced exactly; prose is
condensed.

Types live in the SwiftPM target `AirMouseProtocol` (`Packages/AirMouseKit/Sources/AirMouseProtocol`)
— decisions Addendum C1 renamed this from the spec's original `AirMouseWire`; you may still see
the old name in `03-specifications.md` §6.1's table.

## Changelog

Protocol major version **1** has not shipped yet (no tagged release exists). Once it does,
additive changes (new message types, optional fields, enum values, capabilities) are listed
here without a version bump; breaking changes get a new major version and a dated entry.
See [`CHANGELOG.md`](../CHANGELOG.md) "Protocol" sections for the release-by-release view.

- **Unreleased** — initial definition of protocol version 1, as below.

---

## 1. Conventions and global limits

| Item | Value |
|---|---|
| Byte order | Little-endian for every integer on both channels, including the TCP length prefix |
| Protocol version | `1` (integer), independent of app semantic versions |
| Text encoding | UTF-8 everywhere; JSON per RFC 8259 |
| Hashes | SHA-256; "fingerprint" (FP) = SHA-256 over the DER-encoded X.509 certificate, 32 bytes |
| Base64 | base64url without padding (RFC 4648 §5) wherever "b64u" appears |
| Max control frame | 262 144 bytes (256 KiB) payload; larger → `protocol.frameTooLarge`, connection closed |
| Max UDP datagram | 44 bytes exactly (28-byte AEAD framing + 16-byte payload); any other length is dropped silently |
| Max simultaneous sessions | 4 authenticated + 2 pending; a 7th TCP connection is closed immediately |
| Max trusted devices | 20 per host; 10 trusted hosts per client |
| Control message rate | ≤ 200 messages/s per session (token bucket, burst 400); excess → `rate.limited` then close |

Full detail: spec §3.0.

## 2. Discovery

The host registers Bonjour services **`_airmouse._tcp`** (control) and **`_airmouse._udp`**
(motion) with the same instance name and TXT record; the client browses only `_airmouse._tcp`.
`includePeerToPeer = false` on both sides (no AWDL). Full detail: spec §3.1.1.

### TXT record keys

| Key | Value | Encoding | Example |
|---|---|---|---|
| `v` | Supported protocol major versions, comma-separated ascending | ASCII digits | `1` |
| `n` | Host display name (≤ 63 bytes UTF-8) | UTF-8 | `Devashish's Mac mini` |
| `id` | Host ID: 16 random bytes, stable per install | b64u (22 chars) | `k3Jq…` |
| `fp` | First 16 bytes of the host certificate FP | b64u (22 chars) | `Zx8…` |
| `m` | Machine model identifier | ASCII | `Mac15,6` |
| `tp` | TCP control port | ASCII decimal | `47800` |
| `up` | UDP motion port | ASCII decimal | `47800` |

Each key/value pair ≤ 255 bytes; total TXT ≤ 400 bytes. Full detail: spec §3.1.2.

### QR payload

```
airmouse://pair?v=1&id=<hostID>&n=<name>&a=<addr1,addr2,…>&p=<tcpPort>&u=<udpPort>&fp=<certFP>&s=<secret>
```

| Param | Required | Encoding | Size | Semantics |
|---|---|---|---|---|
| `v` | yes | decimal | 1–3 chars | Protocol major version the QR format belongs to |
| `id` | yes | b64u of 16 bytes | 22 | Host ID (same as TXT `id`) |
| `n` | yes | percent-encoded UTF-8 | ≤ 63 bytes decoded | Host display name |
| `a` | yes | comma-separated literal IPv4/IPv6 (no brackets, no zone) | 1–6 addresses | Ordered: hotspot/bridge → Wi-Fi → Ethernet → link-local IPv6 last |
| `p` | yes | decimal | ≤ 5 | TCP port |
| `u` | no | decimal | ≤ 5 | UDP port; default = `p` |
| `fp` | yes | b64u of 32 bytes | 43 | Full host certificate FP, pinned before the first byte of TLS |
| `s` | yes | b64u of 16 bytes | 22 | One-time pairing secret (128-bit CSPRNG) |

Total URL ≤ 512 bytes. The one-time secret has a **60 s lifetime**, is consumed on the first
successful `pairConfirm`, and is invalidated after 3 failed proofs. It is never logged and
never sent on the wire directly (see the proof construction below). Full detail: spec §3.1.3–3.1.4.

## 3. Pairing handshake

Both sides use self-signed P-256 X.509 certificates over mutual TLS 1.3 (`sec_protocol_options_set_peer_authentication_required(true)`),
pinned by SHA-256 fingerprint — the client pins the QR's `fp`; the host accepts an unknown
certificate only while a Pairing window is open. Full detail: spec §3.2.1–3.2.2.

### Proof construction (channel binding)

```
exporter  = TLS 1.3 exporter, label "EXPORTER-airmouse-pairing-v1", empty context, 32 bytes
binding   = exporter(32) ‖ nonce(16) ‖ clientFP(32) ‖ hostFP(32) ‖ hostID(16)      // 128 bytes
proof     = HMAC-SHA256(key = S, data = 0x01 ‖ binding)                              // client → host
hostProof = HMAC-SHA256(key = S, data = 0x02 ‖ binding)                              // host → client
```

Both values are transmitted b64u-encoded in JSON; `S` never leaves the QR. If
`sec_protocol_metadata_create_secret` proves unavailable on either platform, `exporter` is
replaced with 32 zero bytes and both sides advertise `"pair-binding-certs"` — the mTLS
handshake and nonce freshness still make the binding sound. Full detail: spec §3.2.3.

### Sequence (abbreviated — see spec §3.2.2 for the full mermaid diagram)

1. Mac opens a Pairing window: generates secret `S` (16 B, 60 s lifetime), shows QR.
2. Phone scans QR, pins `fp`, opens TCP + TLS 1.3 (mutual cert exchange).
3. Phone sends `hello { pairing: true, … }`.
4. Mac sends `pairChallenge { nonce, hostID, hostName }`.
5. Phone computes `exporter`, sends `pairProof { proof }`.
6. Mac recomputes and constant-time-compares; on success persists the client cert as trusted,
   consumes `S`, sends `pairConfirm { hostProof }`.
7. Phone verifies `hostProof`, persists the host cert as trusted.
8. Mac sends `helloAck`, `sessionKey`, `hostState`, `macroList`; phone sends `settings`. The
   session is now authenticated, identical to a reconnect from here on.

### Trusted-device persistence

| Side | Store | Record |
|---|---|---|
| Host | Keychain (`kSecClassCertificate`) + `TrustedDevices.json` | `clientID` (FP), `name`, `model`, `osVersion`, `firstPaired`, `lastSeen`, `localAlias?`, `allowScripts` (false), `revoked` (false) |
| Client | Keychain (`kSecClassCertificate`) + `TrustedHosts.json` | `hostID`, `hostFP`, `name`, `model`, `firstPaired`, `lastConnected`, `lastKnownAddresses[]` (≤ 6), `tcpPort`, `udpPort`, `qrAddresses[]`, `perHostSettingsOverride?`, `macroCacheRevision` |

The certificate is the source of truth for trust; a JSON record with no matching Keychain
certificate is dropped on load. Full detail: spec §3.2.4–3.2.6 (failure cases and error codes).

## 4. Reconnect of a trusted device

1. Client resolves a target address (see below) and opens TCP + TLS with the pinned host FP.
2. Client sends `hello` immediately after `.ready`.
3. Host replies with `helloAck`, `sessionKey`, `hostState`, `macroList` (if revision changed)
   back-to-back without waiting.
4. Client sends `settings`, opens the UDP connection, sends the first probe, begins heartbeats.

A new `sessionKey` (new UDP session ID + secret) is issued on **every** TLS connection —
UDP keys are never reused across TCP connections. Full detail: spec §3.3.1.

**Address selection** (spec §3.3.2): candidate order is (1) current Bonjour result for this
`hostID`, (2) `lastKnownAddresses` newest first, (3) `qrAddresses` in QR order. First candidate
not `.ready` within 700 ms → try the next in parallel (staggered happy-eyeballs); per-candidate
timeout 4 s; first `.ready` wins. Non-private-range addresses are skipped unless they came from
a QR scan.

## 5. Control channel (TCP / TLS)

### Framing

```
offset  size  field
0       4     length   u32 LE — number of bytes following this field (1 + body), 1 ≤ length ≤ 262 145
4       1     kind     u8: 0x01 = JSON message, 0x02 = motion batch (binary, §7.4 below)
5       n     body
```

Unknown `kind` → `protocol.badFrame`, close. Full detail: spec §3.4.1.

### Envelope

Every `kind = 0x01` body is one JSON object:

```json
{ "v": 1, "t": "click", "i": 1042, "p": { "button": "left", "action": "tap", "count": 1, "modifiers": [] } }
```

| Field | Type | Meaning |
|---|---|---|
| `v` | int | Protocol major version of this message |
| `t` | string | Message type (camelCase) |
| `i` | uint32 | Sender-local monotonically increasing message id |
| `p` | object | Payload; MAY be omitted when empty |

Unknown `t` → ignored and counted, never fatal. Unknown fields → ignored. Missing required
fields → `protocol.badMessage`, message dropped; three in 10 s → close. JSON encoding uses
`JSONEncoder` with `[.sortedKeys, .withoutEscapingSlashes]`, dates as `Int` ms since epoch,
enums as `rawValue` strings, binary fields as b64u strings. Full detail: spec §3.4.2–3.4.3.

### Version negotiation

`hello.protocol = { "min": 1, "max": 1 }`; the host picks the highest common version in
`max(clientMin, hostMin) … min(clientMax, hostMax)`; empty range → `error protocol.versionMismatch`
and close. Optional features are advertised as strings in `capabilities` (v1 set:
`"tcp-motion-fallback"`, `"pair-binding-certs"`, `"udp-probe"`, `"unicode-text"`,
`"macro-scripts"`). Full detail: spec §3.4.4.

### Message catalogue

Direction: C→H client to host, H→C host to client. Types: `str`, `int`, `num` (double), `bool`,
`b64u`, `[…]` array, `enum(a|b)`. `?` = optional. **This table is reproduced verbatim from spec
§3.4.5** — see there if a field's exact semantics matter for your change.

**`hello`** (C→H, first message)

| Field | Type | Notes |
|---|---|---|
| `protocol.min`, `protocol.max` | int | Supported range |
| `capabilities` | [str] | |
| `device.name` | str ≤ 63 | `UIDevice.current.name` |
| `device.model` | str | e.g. `iPhone16,1` |
| `device.os` | str | e.g. `iOS 18.6` |
| `device.app` | str | app version |
| `pairing` | bool | true → expect `pairChallenge` |
| `macroRevision` | int? | cached macro list revision for this host; host skips `macroList` if equal |
| `displayHz` | int | 60 or 120; informational |

**`pairChallenge`** (H→C): `nonce` b64u(16), `hostID` b64u(16), `hostName` str, `expiresInMs` int.
**`pairProof`** (C→H): `proof` b64u(32).
**`pairConfirm`** (H→C): `hostProof` b64u(32), `hostModel` str.

**`helloAck`** (H→C)

| Field | Type | Notes |
|---|---|---|
| `protocol` | int | chosen version |
| `capabilities` | [str] | |
| `host.name`, `host.model`, `host.os`, `host.helper` | str | |
| `host.id` | b64u(16) | |
| `udpPort` | int | |
| `heartbeatMs` | int | 500 |
| `sessionTimeoutMs` | int | 2000 |
| `maxTextBytes` | int | 16384 |
| `sessionCount` | int | other connected devices |

**`sessionKey`** (H→C): `sessionID` int (u32), `secret` b64u(32), `validForMs` int (14 400 000).

**`settings`** (C→H; on connect and on any change; full snapshot)

| Field | Type | Range / default |
|---|---|---|
| `sensitivity` | int | 1–10, default 5 |
| `acceleration` | enum(off\|precise\|default\|fast) | default `default` |
| `scrollSpeed` | int | 1–10, default 5 |
| `scrollDirection` | enum(host\|natural\|inverted) | default `host` |
| `momentum` | bool | default true |
| `doubleClickIntervalMs` | int | 150–600, default 300 |
| `pinchMode` | enum(keys\|zoomScroll\|off) | default `keys` |
| `textRateCharsPerSec` | int | 50–2000, default 500 |

**`click`** (C→H)

| Field | Type | Notes |
|---|---|---|
| `button` | enum(left\|right\|middle) | |
| `action` | enum(down\|up\|tap) | `tap` = host posts down, waits ≥ 15 ms, posts up |
| `count` | int | 1–3 → `mouseEventClickState`; host clamps to 1 if the previous click of the same button was > 1.5 × `doubleClickIntervalMs` ago |
| `modifiers` | [enum(cmd\|opt\|ctrl\|shift\|fn)] | applied as event flags |

**`scrollPhase`** (C→H): `phase` enum(began\|ended\|cancel), `vx`, `vy` num? (px/s at lift, only
with `ended`), `momentum` bool? (with `ended`). Deltas themselves travel on the motion channel.

**`modifiers`** (C→H): `flags` [enum(cmd\|opt\|ctrl\|shift\|fn\|capsLock)] — absolute set
currently held/locked; host diffs and posts `flagsChanged` per changed key.

**`key`** (C→H)

| Field | Type | Notes |
|---|---|---|
| `code` | int | macOS virtual keycode (ANSI table, spec Appendix 11.2) |
| `char` | str? | Single character when printable; host re-resolves on its current input source |
| `action` | enum(down\|up\|tap) | held keys auto-repeat host-side |
| `modifiers` | [enum] | as in `click` |

**`text`** (C→H): `s` str (1–16 384 bytes UTF-8, grapheme clusters never split across messages),
`secure` bool (host disables its own debug echo; no other wire effect).
**`deleteBackward`** (C→H): `count` int 1–1000, `forward` bool (default false).
**`mediaKey`** (C→H): `key` enum(playPause\|next\|previous\|fastForward\|rewind\|volumeUp\|volumeDown\|mute\|brightnessUp\|brightnessDown\|illuminationUp\|illuminationDown), `action` enum(tap\|down\|up).
**`volume`** (C→H): `level` num 0.0–1.0, `mute` bool?.
**`macroInvoke`** (C→H): `id` str (UUID), `confirmed` bool.
**`recenter`** (C→H): no payload.
**`motionEnd`** (C→H): no payload; also carried as a UDP flag; idempotent.
**`heartbeat`** (C→H): `seq` int, `t1` int (client monotonic µs).
**`pong`** (H→C): `seq`, `t1` (echoed), `t2` int (host µs at receive), `t3` int (host µs at
send), `motion.clientTs` int?, `motion.hostTs` int?, `injectP50Us` int?.

**`hostState`** (H→C; full snapshot on connect and on any change)

| Field | Type | Notes |
|---|---|---|
| `paused` | bool | "Pause input" |
| `accessibility` | bool | `AXIsProcessTrusted()` |
| `naturalScroll` | bool | `com.apple.swipescrolldirection` |
| `displays` | [{`id` int, `x`,`y`,`w`,`h` int, `scale` num, `main` bool}] | |
| `frontmostApp` | {`bundleID` str, `name` str}? | |
| `inputSource` | {`id` str, `ansi` bool} | |
| `scriptsAllowed` | bool | global AND per-device |
| `sessionCount` | int | |

**`macroList`** (H→C): `revision` int, `macros` [Macro]. Full replacement.
**`macroResult`** (H→C): `ref` int (the `i` of the `macroInvoke`), `id` str, `ok` bool,
`message` str ≤ 120, `code` enum(ok\|notFound\|blockedByPolicy\|confirmationRequired\|timeout\|failed).
**`error`** (both): `code` str (dotted namespace: `protocol.*`, `auth.*`, `pairing.*`, `rate.*`,
`host.*`, `macro.*`, `internal`), `message` str, `ref` int?, `fatal` bool.
**`goodbye`** (both): `reason` enum(userQuit\|background\|revoked\|replaced\|hostQuit\|sleep\|error).

### Heartbeat and session timeout

Client sends `heartbeat` every 500 ms from `helloAck`; host answers `pong` immediately. No
`heartbeat` for 2000 ms → host releases all held buttons/modifiers/keys, marks the session
`stale`, stops accepting its motion; no heartbeat for 6000 ms → close TCP. No `pong` for 2000 ms
→ client state `Reconnecting`, keeps the old connection open until the new one is `.ready` or
6 s pass. Full detail: spec §3.4.6.

## 6. Motion channel (UDP)

### Datagram layout (44 bytes)

```
offset  size  field       description
0       4     sessionID   u32 LE, from sessionKey; selects keys + replay window
4       8     counter     u64 LE, per-direction, strictly increasing; doubles as sequence number
12      16    ciphertext  ChaCha20-Poly1305 encryption of the 16-byte payload
28      16    tag         Poly1305 tag
```

AAD = bytes 0–11 (header). Anything not exactly 44 bytes, with an unknown `sessionID`, or
failing authentication is dropped silently and counted.

### Payload layout (16 bytes, plaintext)

```
offset  size  field       description
0       1     flags       bit0 scrollBegan · bit1 scrollEnded · bit2 motionEnd · bit3 predicted · bit4 probe · bit5 echo · bits6–7 reserved (0)
1       1     source      0 touch · 1 gyro · 2 external pointer (iPad trackpad/mouse) · 3 tcpFallback (host bookkeeping only) · 255 probe
2       1     samples     number of raw sensor samples coalesced into this datagram, 1–255 (0 for probe)
3       1     reserved    must be 0
4       4     timestamp   u32 LE, client monotonic clock in µs (wraps every 71.6 min; modular arithmetic)
8       2     dx          i16 LE, pointer delta X in 1/8 point (±4095.875 pt per datagram)
10      2     dy          i16 LE, pointer delta Y (positive = down)
12      2     scrollX     i16 LE, scroll delta X in 1/8 point (finger-travel units)
14      2     scrollY     i16 LE, scroll delta Y
```

The "sequence number" is the low 32 bits of the header `counter`. Full detail: spec §3.5.1–3.5.2.

### Keys and nonces

```
kC2H = HKDF-SHA256(ikm = secret, salt = sessionID as u32 LE (4 B), info = "airmouse-udp-c2h-v1", L = 32)
kH2C = HKDF-SHA256(ikm = secret, salt = sessionID as u32 LE (4 B), info = "airmouse-udp-h2c-v1", L = 32)
nonce = 0x00 0x00 0x00 0x00 ‖ counter as u64 LE (8 B)            // 12 bytes
```

A sender that reaches counter 2³² SHALL stop sending and request/issue a new key. Full detail:
spec §3.5.3.

### Replay window (RFC 6479 style, W = 64)

```
if counter > highest:            shift bitmap left by (counter − highest) (saturating), set bit0, highest = counter, accept
elif highest − counter ≥ 64:     drop (too old)
elif bitmap bit (highest − counter) set: drop (replay)
else:                            set bit, accept
```

Runs **after** AEAD authentication succeeds. Separately, an accepted datagram whose counter is
more than 8 below the highest *applied* counter has its deltas discarded (avoids visible jumps
from very-late arrivals); datagrams within the 8-window apply in arrival order. Full detail:
spec §3.5.4.

### Key rotation

A new `sessionKey` is issued on every TCP connection. The host additionally rotates when either
direction's counter reaches 2³¹ or 4 h after issue; the client switches on receipt; the host
keeps accepting the previous `sessionID` for 2 s. Two keys maximum are live per session. Full
detail: spec §3.5.5.

### Loss, reordering, probe/fallback

No retransmission. No motion datagram for 100 ms while a stream was active → host treats the
stream as paused. Prediction is **off by default in v1**. `motionEnd` flag zeroes velocity and
remainder. Full detail: spec §3.5.6–3.5.7.

| Rule | Value |
|---|---|
| Probe interval, connected | 250 ms (4 Hz) |
| Probe window | last 12 probes (3 s) |
| Enter TCP fallback | ≥ 11 of 12 unanswered (≥ 90%) and a `pong` in the last 1 s — or the first 8 probes after connect all unanswered (2 s) |
| In fallback | motion sent as `kind = 0x02` frames, ≤ 60 frames/s; "Elevated latency" badge shown; probes continue at 1 Hz |
| Exit fallback | 5 consecutive probes answered |

Full detail: spec §3.5.8.

### TCP motion batch frame

`kind = 0x02`, body = n × 16-byte payloads (1 ≤ n ≤ 16) in the plaintext layout above, `source`
unchanged, no AEAD (TLS protects it), no counter (TCP is ordered). Full detail: spec §3.5.9.

## 7. Scroll and gesture semantics

Scroll deltas are finger travel in points × 8 (i16); host converts to pixels via a geometric
`scrollGain(1…10)` from 0.5 to 3.0 (default 5 → 1.22), then applies direction. Momentum: the
**client** decides (fling velocity, its `momentum` setting, cancel-on-touch) and the **Mac
synthesizes** the decay at 60 Hz (`v ← v · exp(−Δt/τ)`, τ = 350 ms) so momentum survives
datagram loss. Full detail: spec §3.6.

## 8. Versioning and compatibility policy

- **Major version** changes only for incompatible framing, envelope, or crypto changes. Both
  sides support the current and previous major for 12 months after a bump.
- **Additive changes** (new message types, optional fields, enum values, capabilities) do not
  bump the version; receivers ignore what they don't know; senders must not rely on a field the
  peer hasn't advertised via `capabilities`.
- Motion payload layout is frozen within a major; new sources use spare `source` values; spare
  `flags` bits must be zero when sent, ignored when received.
- Deprecations are announced in this file's Changelog section above.

Full detail: spec §3.7.

---

## 9. Test vectors

Vectors live in `Packages/AirMouseKit/Tests/*/Vectors/*.json`, generated by
`scripts/gen-vectors.swift` (CryptoKit on macOS) so any contributor can regenerate them; CI
asserts the checked-in vectors decode and re-encode byte-exactly (spec §6.4).

- **Motion payload**: `{flags:0x00, source:0, samples:1, ts:0x00012345, dx:+80 (10 pt), dy:−8
  (−1 pt), sx:0, sy:0}` → hex `00 00 01 00 45 23 01 00 50 00 F8 FF 00 00 00 00`.
- **AEAD framing**: inputs `secret = 0x00…1F` (32 bytes counting up), `sessionID =
  0x0A0B0C0D`, direction c2h, `counter = 7`; the vector records `kC2H`, the nonce
  `00 00 00 00 07 00 00 00 00 00 00 00`, the AAD `0D 0C 0B 0A 07 00 00 00 00 00 00 00`, and the
  44-byte datagram. Asserts `open` returns the payload above, that flipping any bit fails, and
  that re-opening the same datagram is rejected by the replay window.
- **Replay window**: sequence `[0,1,2,1,70,5,6,70,200,136,135]` → accept/reject pattern
  `[A,A,A,R,A,R,A,R,A,A,R]` (5 and 6 are ≥ 64 behind 70; 136 is exactly 64 behind 200 →
  rejected; 135 rejected).
- **Pairing proof**: fixed `S`, `exporter`, `nonce`, FPs, `hostID` → expected `proof` and
  `hostProof` hex; plus a negative vector with one byte of `hostID` changed.
- **One-Euro**: a 200-sample synthetic angle trace (sine 0.5 Hz + white noise σ = 0.3°) filtered
  with (1.0, 1.0, 1.0) → expected outputs to 1e-9; a step test asserting lag ≤ 8 ms at 20°/s for
  `minCutoff = 0.5`.
- **Acceleration curve**: the `base(s)` table (spec §5.4) and `accel(v)` at v ∈ {0, 750, 1500, 3000}.
- **QR**: canonical URL ↔ struct round trip, plus malformed cases (missing `s`, 513 bytes, IPv6
  with brackets).

---

For anything not covered above — module dependency graph, threading model, security threat
model beyond the wire, or the app-side feature specs — see
[`docs/03-specifications.md`](03-specifications.md) and [`docs/04-architecture.md`](04-architecture.md).
