// Services/MotionPublisher/MotionPublisherStatusAdapter.swift
// Thin `@MainActor` facade satisfying the shell's `MotionPublishing` (App/ServiceProtocols.swift)
// on behalf of the `MotionPublisher` actor. An `actor` cannot itself conform to
// `MotionPublishing` — that protocol is declared `@MainActor`, and Swift does not allow an actor
// type to conform to a global-actor-isolated protocol (confirmed by the compiler: "actor
// 'MotionPublisher' cannot conform to global-actor-isolated protocol 'MotionPublishing'"), even
// when every satisfying member is written `nonisolated`. This adapter is what
// `TouchpadFeature`/`AppEnvironment` wiring plugs into `AppEnvironment.motion` instead.

import Observation

@MainActor
@Observable
public final class MotionPublisherStatusAdapter: MotionPublishing {
    private let publisher: MotionPublisher

    public init(publisher: MotionPublisher) {
        self.publisher = publisher
    }

    /// Reads `MotionPublisher.isPublishing` directly — that property is `nonisolated` (lock-backed),
    /// so no actor hop is needed here.
    public var isPublishing: Bool { publisher.isPublishing }
}
