// Features/Diagnostics/LogViewerView.swift
// Stub log viewer, reachable from Settings › Advanced "Diagnostics log export" (spec §4.1.9).
// A full implementation (reading `OSLogStore`, filtering by `Log` category, and driving a Save
// panel/share sheet for `diagnostics/1` export, arch §8) is future work; this stub establishes
// the navigation destination and accessibility shape so Settings can link to it now.

import SwiftUI

public struct LogViewerView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView {
            Label {
                Text("Log viewer coming soon", comment: "Diagnostics log viewer stub title")
            } icon: {
                Image(systemName: "doc.text.magnifyingglass")
            }
        } description: {
            Text("On-device log viewing and export isn't implemented yet.", comment: "Diagnostics log viewer stub description")
        }
        .navigationTitle(Text("Diagnostics Log", comment: "Diagnostics log viewer navigation title"))
        .airControlDynamicTypeRange()
    }
}

#Preview {
    NavigationStack { LogViewerView() }
}
