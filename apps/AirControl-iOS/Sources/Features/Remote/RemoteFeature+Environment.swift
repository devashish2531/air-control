// Features/Remote/RemoteFeature+Environment.swift
// Integration factory. `RootTabView.swift` (owned by another agent, not touched here) currently
// calls the zero-argument `RemoteScreen()`; once the Connection agent's sink adapter exists, the
// integration agent switches that call site to `RemoteFeature.make(environment:sink:)` to inject
// the real `AppEnvironment` and a concrete `RemoteCommandSink`.

import SwiftUI

public enum RemoteFeature {
    @MainActor
    public static func make(environment: AppEnvironment, sink: any RemoteCommandSink) -> some View {
        RemoteScreen(environment: environment, sink: sink)
    }
}
