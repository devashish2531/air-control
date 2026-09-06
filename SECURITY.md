# Security Policy

Air Control posts synthesized keyboard/mouse input to your Mac and moves data across your local
network. We take reports about it seriously. See also
[`docs/03-specifications.md`](docs/03-specifications.md) §7 for the full threat model and
[`docs/protocol.md`](docs/protocol.md) for the wire protocol — **reports about the protocol or
architecture itself, not just a specific implementation bug, are welcome.**

## Supported versions

Only the **latest minor release of the current major version** is supported with security
fixes, on both iOS and macOS. There is no long-term support branch while the project is
pre-1.0.

| Version | Supported |
| --- | --- |
| Latest `0.x` minor | ✅ |
| Older `0.x` minors | ❌ |

This table will grow a row per major version once `1.0` ships.

## Reporting a vulnerability

**Please report privately — do not open a public issue.**

Preferred: use [GitHub Security Advisories](https://github.com/OWNER/air-control/security/advisories/new)
for this repository ("Report a vulnerability" under the Security tab).

Alternative: email **security@\<project domain\>** once a project domain exists (placeholder —
not yet live; use the GitHub Security Advisory form until it is).

If you'd like to encrypt your report, use this PGP key (placeholder — replace with the
maintainer's real key before this file goes live):

```
-----BEGIN PGP PUBLIC KEY BLOCK-----

PLACEHOLDER — a maintainer must generate a real key and paste the
public block here (and publish it on a keyserver) before relying on
this for encrypted reports.

-----END PGP PUBLIC KEY BLOCK-----
```

Please include:

- What you found and why it's a vulnerability (which threat in §7.1 of the spec it maps to,
  if you can tell).
- Steps to reproduce, or a minimal proof of concept.
- Affected version(s)/platform(s).
- Your assessment of severity/impact, if you have one.

**Please do not** include real pairing secrets, private key material, or another user's data
in your report.

## What to expect

- **Acknowledgement within 72 hours** of a report being received.
- We aim for **coordinated disclosure within 90 days** of acknowledgement, or sooner by mutual
  agreement — whichever the fix and any downstream coordination allow.
- We will keep you updated on progress and let you know before we publish.
- With your permission, we credit reporters by name (or handle) in the release notes and/or a
  GitHub Security Advisory.
- No release ships with a known open high-severity finding (plan §6, security review gate).

## Scope

In scope:

- `Packages/AirControlKit` (protocol, crypto, filters, core session logic, `aircontrol-cli`).
- `apps/AirControl-iOS` and `apps/AirControl-Mac` (the shipped apps and helper).
- The wire protocol and pairing/trust model documented in `docs/03-specifications.md` §3, §7
  and `docs/protocol.md` — design-level issues, not just implementation bugs, are welcome.
- Release infrastructure (`.github/workflows/release.yml`, `scripts/release/*`,
  `Formula/Casks/air-control.rb`) — e.g. supply-chain or signing/notarization concerns.

Out of scope:

- Denial of service that requires the attacker to already be an authenticated, trusted device
  (that trust boundary is intentional — see spec §7.1 T9 for the one place this is explicitly
  mitigated anyway).
- Social engineering of a user into scanning someone else's pairing QR code.
- Findings that only reproduce on a jailbroken/rooted device or a modified build.
- Third-party dependencies' own CVEs — please report those upstream (`swift-certificates`,
  `swift-argument-parser`, Sparkle); we track and update them via Dependabot, but coordinate
  disclosure with the upstream project.

Thank you for helping keep Air Control's users safe.
