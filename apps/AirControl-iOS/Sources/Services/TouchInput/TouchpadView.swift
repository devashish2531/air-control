// Services/TouchInput/TouchpadView.swift
// `UIViewRepresentable` bridge over `TouchpadUIView` (spec §4.2.1's mandated UIKit-under-SwiftUI
// pattern — see docs/02-technical-research.md C1: SwiftUI `DragGesture` has no per-touch identity,
// no multi-touch, no `coalescedTouches`/`predictedTouches`).

import SwiftUI
import AirControlFilters

public struct TouchpadView: UIViewRepresentable {
    public var config: GestureConfig
    public var predictionEnabled: Bool
    public weak var intentSink: (any TouchpadIntentSink)?

    public init(config: GestureConfig, predictionEnabled: Bool, intentSink: (any TouchpadIntentSink)?) {
        self.config = config
        self.predictionEnabled = predictionEnabled
        self.intentSink = intentSink
    }

    public func makeUIView(context: Context) -> TouchpadUIView {
        let view = TouchpadUIView()
        view.config = config
        view.predictionEnabled = predictionEnabled
        view.intentSink = intentSink
        // On-device UI test hook only: stable identifier for the touch surface. No behaviour change.
        view.accessibilityIdentifier = "touchpad.surface"
        return view
    }

    public func updateUIView(_ uiView: TouchpadUIView, context: Context) {
        uiView.config = config
        uiView.predictionEnabled = predictionEnabled
        uiView.intentSink = intentSink
    }
}
