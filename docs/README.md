# Air Mouse — Planning Documents

Documents are numbered in the order they were produced; each builds on the previous.
Precedence when they disagree: `00-decisions.md` (addenda included) > `04-architecture.md` > `03-specifications.md` > `02` > `01`.

| # | File | Purpose | Status |
|---|------|---------|--------|
| 00 | `00-decisions.md` | Stakeholder decisions from the requirements interview, plus addenda A–C (provisional choices awaiting owner confirmation) | Complete |
| 01 | `01-requirements.md` | PRD: personas, 84 user stories, ~110 FR/NFR, 20-item risk register | Complete |
| 02 | `02-technical-research.md` | Apple API feasibility research, latency budget, prior art, spike list | Complete |
| 03 | `03-specifications.md` | Functional & technical spec: wire protocol, state machines, iOS/Mac module specs, security, tests | Complete |
| 04 | `04-architecture.md` | System architecture: package layout, XcodeGen projects, module diagrams, runtime views, concurrency, CI/CD, ADR-001…015 | Complete |
| 05 | `05-plan.md` | Delivery plan: M0–M9 roadmap, 158-task WBS, critical path, quality gates, M0 runbook, backlog | Complete |
| 06 | `06-implementation-log.md` | Running record of the build: environment, bootstrap, parallel agent waves, integration, end-to-end results | Complete (v0.1 code) |

## Owner decisions still open
See the addenda in `00-decisions.md`. Defaults stand unless overridden:
- License: MIT vs Apache-2.0 (A7)
- Transport: TCP+mTLS control + AEAD UDP motion, QUIC deferred (A1–A3)
- Project name: "Air Mouse" collides on the App Store (A8)
- Momentum locus: client decides, host runs decay (B1)

## Next step
Run the M0 runbook in `05-plan.md` §8, then file the first 10 issues listed there.
