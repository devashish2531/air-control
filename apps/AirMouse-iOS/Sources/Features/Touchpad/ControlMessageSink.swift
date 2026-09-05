// Features/Touchpad/ControlMessageSink.swift
// Output boundary for the reliable (TCP/TLS) control-channel effects the Touchpad feature needs
// (spec §3.4.5 `click`/`scrollPhase`/`settings`). Mirrors `RemoteCommandSink`
// (Features/Remote/RemoteCommandSink.swift)'s pattern: this module owns no networking
// (CLAUDE.md), so every wire effect goes through this one protocol, which the Connection agent's
// concrete session type (or a thin adapter over it) conforms to.
//
// Deliberately minimal, per this agent's assignment ("define minimal: `sendClick`,
// `sendScrollPhase`, `sendSettings`; the connection agent will implement it") — see this agent's
// final-report deviation note: spec §4.2.5's `key`-message gestures (three-finger swipe, pinch in
// Keys mode, four-finger tap) have no send path through this sink yet and are currently
// recognized-but-unsent by `TouchpadController`.

import AirMouseProtocol

@MainActor
public protocol ControlMessageSink: AnyObject {
    func sendClick(_ click: Click)
    func sendScrollPhase(_ phase: ScrollPhase)
    func sendSettings(_ settings: Settings)
}

/// Default stand-in until `TouchpadFeature.make(environment:motion:controlSink:)` injects the
/// real sink.
@MainActor
public final class NoOpControlMessageSink: ControlMessageSink {
    public init() {}

    public func sendClick(_ click: Click) {
        Log.app.notice("NoOpControlMessageSink.sendClick — no Connection agent wired yet")
    }

    public func sendScrollPhase(_ phase: ScrollPhase) {
        Log.app.notice("NoOpControlMessageSink.sendScrollPhase — no Connection agent wired yet")
    }

    public func sendSettings(_ settings: Settings) {
        Log.app.notice("NoOpControlMessageSink.sendSettings — no Connection agent wired yet")
    }
}
