// Features/Keyboard/Keyboard+Environment.swift
// Integration point for wiring a real `KeyboardEventSink` once the Connection agent's transport
// exists. This module deliberately does not edit `App/ServiceProtocols.swift` or
// `App/AppEnvironment.swift` (per this agent's assignment) — instead, whoever composes the real
// `AppEnvironment` (the app's composition root / the integration agent) calls
// `KeyboardFeature.makeBridge(sink:)` and assigns the result into `AppEnvironment.keyboard`:
//
//     let keyboardBridge = KeyboardFeature.makeBridge(sink: realKeyboardEventSink)
//     let environment = AppEnvironment(..., keyboard: keyboardBridge, ...)
//
// `KeyboardScreen()` (constructed by `RootTabView` with no arguments) then discovers that same
// bridge through `environment.keyboard` on its own — see `KeyboardScreen`'s doc comment — so nothing
// else needs to change at the call site in `RootTabView.swift`. `KeyboardFeature.make(environment:
// sink:)` is provided as an explicit alternative for anyone who prefers to construct the screen
// directly (tests, or a future `RootTabView` that passes the environment through explicitly).

import SwiftUI

@MainActor
public enum KeyboardFeature {
    /// Builds a `KeyboardBridge` (conforms to `ServiceProtocols.KeyboardBridging`) over `sink`,
    /// suitable for `AppEnvironment(keyboard:)` once a real `KeyboardEventSink` exists.
    public static func makeBridge(sink: any KeyboardEventSink = NoOpKeyboardEventSink()) -> KeyboardBridge {
        KeyboardBridge(sink: sink)
    }

    /// Builds the Keyboard tab's screen directly, wired to `sink` (defaults to
    /// `NoOpKeyboardEventSink` so the app builds/runs/previews standalone) and `environment`'s
    /// `HapticsService` (spec §4.6).
    public static func make(environment: AppEnvironment, sink: any KeyboardEventSink = NoOpKeyboardEventSink()) -> KeyboardScreen {
        let bridge = (environment.keyboard as? KeyboardBridge) ?? KeyboardBridge(sink: sink)
        return KeyboardScreen(bridge: bridge, haptics: environment.haptics)
    }
}
