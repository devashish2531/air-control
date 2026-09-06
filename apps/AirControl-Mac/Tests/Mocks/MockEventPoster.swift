// Test-facing name for `RecordingEventPoster` (Services/EventInjector/RecordingEventPoster.swift),
// matching this test target's other `Mock*` doubles (`MockTrustStore`) so EventInjector/MomentumEngine
// suites — and any other suite in this target that wants to assert on posted events — can spell it the
// way the rest of the target's mocks are spelled, without needing to know the production type also
// backs the app's `--loopback` mode. Deliberately just an alias, not a second implementation: the
// assignment asks for `RecordingEventPoster` to be "used by tests AND by the app's `--loopback` mode",
// so there is exactly one implementation to keep the two paths honest with each other.
@testable import Air_Control

typealias MockEventPoster = RecordingEventPoster
