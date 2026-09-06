<!-- arch §9.2 / plan §6 quality gates. Delete sections that truly don't apply, but don't skip the checkboxes. -->

## Summary

<!-- What does this change, and why? -->

## Spec section(s) touched

<!-- Cite the section(s) you read/implemented against, e.g. "spec §3.5.2", "arch §5.3". Required for any behavior change. -->

## Checklist

- [ ] I read the relevant spec/arch section(s) above before writing code (CLAUDE.md rule).
- [ ] Tests added/updated (`swift test` for kit changes; `Mock*`-based view-model tests for app changes; loopback integration test for wire-visible Mac behavior).
- [ ] Builds clean under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY=complete`) — no new `@unchecked Sendable`, no new `Unsafe*` outside `MotionPayload` pack/unpack.
- [ ] No new third-party dependencies beyond `swift-certificates`, `swift-argument-parser`, and (Mac) Sparkle — or this PR is the one adding an approved exception, discussed in an issue first.
- [ ] User-facing strings added go through the String Catalog (`.xcstrings`), not literals — `scripts/check-xcstrings.sh` passes.
- [ ] Protocol change? → bumped the `docs/protocol.md` CHANGELOG section and, if wire-visible, `CHANGELOG.md` under a "Protocol" heading.
- [ ] Storage schema change? → migrator added + `CHANGELOG.md` "Storage" entry.
- [ ] UI change? → screenshots attached, light **and** dark mode.
- [ ] No secrets, logs with typed text, pairing secrets, or full certificate fingerprints included anywhere in this PR (spec §7.4).

## Screenshots (UI changes only)

<!-- Light mode | Dark mode -->

---

<!--
Reviewer note: changes under `Packages/AirControlKit/Sources/AirControlCrypto`, `docs/protocol.md`,
or `.github/workflows/**` require a CODEOWNERS review (arch §9.2).
-->
