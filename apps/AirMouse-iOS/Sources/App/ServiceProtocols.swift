// App/ServiceProtocols.swift
// Minimal protocol slots for the services other agents own (Connection, Motion/Gyro, Keyboard
// bridge, Macros, Pairing). Per CLAUDE.md: "If you need a type owned by another module that does
// not exist yet, write a minimal protocol in your own module and note it in your report." These
// protocols intentionally expose only what `AppEnvironment`/`RootTabView`/the placeholder screens
// need for wiring — the owning agent's concrete type may (and should) be far richer; it just
// needs to conform to these as well, or `AppEnvironment` can be widened once the real type lands.
//
// None of these import Network, CoreMotion, or a touch engine — this module owns no networking
// or sensor code (assignment constraint).

import Foundation
import Observation

// MARK: - Connection

/// Mirrors the state names of the connection state machine (spec §4.5.1) so the shell can render
/// the connection pill and route error banners without depending on the real actor. The owning
/// agent's `ConnectionManager` is expected to publish exactly these cases (it may attach
/// associated data of its own choosing appropriate to its implementation).
public enum ConnectionState: Sendable, Equatable {
    case idle
    case browsing
    case connecting
    case pairing
    case connected(hostName: String)
    case reconnecting(hostName: String)
    case suspended
    case failed(reason: String)
}

/// What the shell needs from the connection service: the current state to render, and the two
/// user-facing verbs the connection pill offers. Everything else (browsing results, trusted
/// hosts, pairing) belongs to the Devices/Pairing features and their own richer protocols.
@MainActor
public protocol ConnectionManaging: AnyObject {
    /// Current connection state; the shell observes this for the connection pill and idle-timer/
    /// keep-awake wiring (spec §4.6).
    var connectionState: ConnectionState { get }
    /// Host display name for the currently-targeted Mac, if any (connection pill label).
    var currentHostName: String? { get }

    func connect() async
    func disconnect() async
}

// MARK: - Motion

/// What the shell needs to know about motion publishing: whether it is active, for idle-timer/
/// screen-awake purposes and Diagnostics wiring. The Motion agent's actor is expected to conform
/// in addition to its full internal API.
@MainActor
public protocol MotionPublishing: AnyObject {
    var isPublishing: Bool { get }
}

// MARK: - Gyro

/// What the shell needs from the gyro engine: availability (to hide the Air Mouse tab per
/// FR-GY-012 / spec §4.1) and lifecycle hooks the AirMouse feature calls on appear/disappear.
@MainActor
public protocol GyroEngineProviding: AnyObject {
    /// `CMMotionManager().isDeviceMotionAvailable` — the Air Mouse tab is hidden when false.
    var isGyroAvailable: Bool { get }
    func start() async
    func stop() async
}

// MARK: - Keyboard

/// What the shell needs from the keyboard bridge: whether it currently owns first responder /
/// hardware passthrough, for iPad ⌘1–⌘5 tab-switching suspension (FR-IP-005, spec §4.1.10).
@MainActor
public protocol KeyboardBridging: AnyObject {
    var isHardwarePassthroughActive: Bool { get }
}

// MARK: - Macros

/// What the shell needs from the macro store: a count for badges/empty states and a refresh
/// hook. The Macros feature owns the full `Macro` model and paging.
@MainActor
public protocol MacroStoreProviding: AnyObject {
    var macroCount: Int { get }
    func refresh() async
}

// MARK: - Pairing routing (deep links)

/// Forwards a scanned or deep-linked pairing URL (`airmouse://pair?...`, spec §4.1.2) to the
/// Pairing feature, which owns `QRPayload` parsing and the pairing sheet. The shell's only job is
/// to recognise the URL scheme/host and hand it off; malformed-URL presentation (E-PAIR-URL) is
/// the Pairing feature's responsibility once it owns a real implementation.
@MainActor
public protocol PairingRouting: AnyObject {
    func routePairing(url: URL)
}
