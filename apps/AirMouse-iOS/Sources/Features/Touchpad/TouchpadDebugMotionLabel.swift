// Features/Touchpad/TouchpadDebugMotionLabel.swift
// DEBUG-only near-invisible label exposing the touch → motion pipeline's live counters, mirroring
// `RootTabView.debugPairingLabel`/`PairingDebugLabel` (App/RootTabView.swift, another agent's
// file, not modified here — this is a same-pattern sibling, not a shared type). Lets an on-device
// or simulator UI test (or a human) confirm that touches actually reaching `TouchpadUIView` turn
// into `MotionPublisher` datagrams, without needing a live Mac connection:
// `MotionPublisher.stats` (Services/MotionPublisher, another agent's file, not modified here) is a
// `nonisolated`, lock-backed snapshot that increments on every `enqueue`/`enqueueScroll` call —
// i.e. every intent the pad/scroll-strip hands to the controller — regardless of whether the
// underlying `MotionDatagramSink` is actually connected to a Mac (`drain()` calls
// `sink.sendMotion(_:)` and bumps `sentDatagramCount` unconditionally). Compiled out of Release.

import SwiftUI

#if DEBUG
struct TouchpadDebugMotionLabel: View {
    let environment: AppEnvironment
    let controller: TouchpadController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let stats = environment.motionPublisher.stats
            let state = String(describing: environment.connection.connectionState)
            let touch = TouchpadUIViewDebugCounters.snapshot
            let summary = "debug.motion touchesBegan=\(touch.began) touchesMoved=\(touch.moved)"
                + " intents=\(controller.debugIntentCount) moves=\(controller.debugMoveIntentCount)"
                + " samples/s=\(String(format: "%.1f", stats.samplesPerSecond))"
                + " coalesced=\(stats.coalescedCount) sent=\(stats.sentDatagramCount)"
                + " queued=\(stats.queuedDatagramCount) dropped=\(stats.droppedDatagramCount) state=\(state)"
            Text(summary)
                .font(.system(size: 6))
                .foregroundStyle(.secondary)
                .opacity(0.02)
                .accessibilityIdentifier("touchpad.debugMotion")
                .accessibilityLabel(summary)
                .allowsHitTesting(false)
        }
    }
}
#endif
