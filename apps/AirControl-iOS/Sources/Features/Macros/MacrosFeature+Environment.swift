// Features/Macros/MacrosFeature+Environment.swift
// Integration factory. See RemoteFeature+Environment.swift's doc comment for the same rationale:
// `RootTabView.swift` currently calls the zero-argument `MacrosScreen()`; the integration agent
// switches that call site to this once a real `RemoteCommandSink` exists. `MacrosScreen` itself
// registers the created `MacrosModel` into `environment.macros` (App/AppEnvironment.swift's
// `MacroStoreProviding` slot) on first appearance, so no extra wiring is needed here.

import SwiftUI

public enum MacrosFeature {
    @MainActor
    public static func make(environment: AppEnvironment, sink: any RemoteCommandSink) -> some View {
        MacrosScreen(environment: environment, sink: sink)
    }
}
