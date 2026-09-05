# Latency rig

Measures the PRD/spec §8.1 latency metric (NFR-PERF-001: control-path RTT p50 ≤ 12 ms, p95 ≤ 20 ms)
against a real Mac over Wi-Fi, using `airmouse-cli bench` instead of a phone — see spec §8.2
("Measurement methodology") and §10.4 ("Performance test procedure") for the full picture this rig
is one piece of.

## What `bench.sh` measures

`airmouse-cli bench` opens a real TLS/UDP session to the Mac helper and, for the run's duration,
streams synthetic 120 Hz motion while sending `heartbeat`/`pong` on the normal 500 ms cadence and
UDP probes at 4 Hz (spec §3.4.6, §3.5.8) — the same traffic pattern a real session produces. At the
end it prints `SessionStats` (spec §8.2): heartbeat RTT p50/p95, probe loss %, motion send rate, and
whether the session fell back to TCP.

## What this does NOT measure

Heartbeat RTT is a good proxy but is **not** the same number as spec §10.4's "ground truth" latency
(finger movement → cursor movement on screen, measured with a 240 fps camera) — RTT includes the
full round trip and misses host-side injection time and display scan-out. Use this rig for quick
day-to-day regression checks and CI-adjacent spot checks; use the camera rig below when you need the
actual NFR-PERF-001 pass/fail number for a release.

## Quick start

1. Pair once, from this machine, with the target Mac (same network):
   ```
   swift run --package-path Packages/AirMouseKit airmouse-cli pair "airmouse://pair?..."
   ```
   (copy the URL from the Mac helper's pairing window/QR).
2. Run the bench script against the Mac's Wi-Fi IP:
   ```
   scripts/latency-rig/bench.sh --host 192.168.1.23 --seconds 10 --rate 120 --label "living-room-5ghz"
   ```
3. Repeat across networks/conditions — each run appends one row to
   `scripts/latency-rig/results.csv` (git-ignored; this directory only ships the tool, not captured
   data) with timestamp, label, host, rate, and the RTT/loss/fallback numbers.

Flags: `--port` (default 47800), `--fingerprint <hex>` (override the saved trust record if pairing
with more than one Mac), `--out <path>` (CSV location).

## Ground-truth camera procedure (spec §10.4 step 1)

For the number that actually gates a release:

1. 120 Hz iPhone, Mac set to 60 Hz and separately to 120 Hz, single 5 GHz AP, phone and Mac both on
   it (no VPN/mesh hop).
2. Record 240 fps video of both the finger on the touchpad/screen and the cursor on the Mac display
   for 20 s of continuous sinusoidal movement.
3. Annotate 30 direction reversals in the footage (a frame-accurate video editor or `xctrace`'s
   frame stepping works); latency for each = (cursor-reversal frame − finger-reversal frame) ÷ 240.
4. Report p50/p95/p99. Pass: p50 ≤ 12 ms + half a display frame, p95 ≤ 20 ms + half a display frame.
5. Cross-check against the in-app Latency HUD's one-way estimate recorded at the same time — spec
   §8.2 requires the two to agree within 3 ms at p50; a bigger gap means the HUD's clock-offset
   estimate (or this rig's assumptions) needs another look before trusting either number.

## Files here

- `bench.sh` — builds `airmouse-cli` in release mode and runs one `bench` measurement, appending a
  CSV row.
- `results.csv` — created on first run; not committed (add your own `.gitignore` entry if you want
  history, or keep results in your own tracking system per the PRD's latency-report issue template,
  `.github/ISSUE_TEMPLATE/latency-report.yml`).
