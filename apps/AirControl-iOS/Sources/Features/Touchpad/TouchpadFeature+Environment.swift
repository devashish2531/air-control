// Features/Touchpad/TouchpadFeature+Environment.swift
// Integration factory, mirroring `RemoteFeature.make(environment:sink:)`
// (Features/Remote/RemoteFeature+Environment.swift). `RootTabView.swift` (owned by another agent,
// not touched here) currently calls the zero-argument `TouchpadScreen()`; once the Motion agent's
// `MotionPublisher` and the Connection agent's control sink adapter exist, the integration agent
// switches that call site to `TouchpadFeature.make(environment:motion:controlSink:)`.

import SwiftUI

public enum TouchpadFeature {
    @MainActor
    public static func make(
        environment: AppEnvironment,
        motion: MotionPublisher,
        controlSink: any ControlMessageSink
    ) -> some View {
        TouchpadScreen(environment: environment, motion: motion, controlSink: controlSink)
    }
}
