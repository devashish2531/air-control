# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
for app versions once `1.0.0` ships; the wire **protocol** version (spec §3.7) is tracked
independently in its own "Protocol" subsection below and is not the same number as the app
version.

## [Unreleased]

### Added

- Nothing yet — project is in initial repository bootstrap (M0).

### Changed

### Fixed

### Protocol

- No protocol version has shipped yet. Protocol major version `1` is defined in
  `docs/03-specifications.md` §3 and extracted for contributors in `docs/protocol.md`; changes
  to either during M0–M2 do not yet need an entry here, but every change from the first tagged
  release onward must record whether it was additive (no version bump) or a breaking major
  version change here, per §3.7's compatibility policy.

<!--
Template for a new release section (copy this above [Unreleased] resets to empty, below the new heading):

## [X.Y.Z] - YYYY-MM-DD

### Added
### Changed
### Fixed
### Storage
(only if a persisted schema changed — include the migrator)

### Protocol
(state the negotiated protocol version this release speaks, and list any additive changes;
call out explicitly if this is a MAJOR protocol version bump per spec §3.7)
-->
