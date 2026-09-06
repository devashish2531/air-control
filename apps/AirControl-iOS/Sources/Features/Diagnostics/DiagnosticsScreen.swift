// Features/Diagnostics/DiagnosticsScreen.swift
// Settings › Diagnostics destination: shows the latency HUD data as a static screen (in addition
// to the overlay other feature screens can opt into via `.latencyHUD(...)`) and links to the log
// viewer stub (spec §4.1.9 Advanced "Diagnostics log export").

import SwiftUI

public struct DiagnosticsScreen: View {
    @Environment(\.appEnvironment) private var environment

    public init() {}

    public var body: some View {
        List {
            Section {
                LatencyHUDView(sample: environment.diagnostics.latest)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("Latency", comment: "Diagnostics screen section header")
            }
            Section {
                NavigationLink {
                    LogViewerView()
                } label: {
                    Text("Log viewer", comment: "Diagnostics screen: navigates to the log viewer stub")
                }
            }
        }
        .navigationTitle(Text("Diagnostics", comment: "Diagnostics screen navigation title"))
        .airControlDynamicTypeRange()
    }
}

#Preview {
    NavigationStack {
        DiagnosticsScreen()
            .environment(\.appEnvironment, .preview())
    }
}
