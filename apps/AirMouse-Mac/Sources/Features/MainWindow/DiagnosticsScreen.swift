// docs/08 §5.2 sidebar item 4 "Diagnostics" — embeds the existing diagnostics view
// (`Features/Diagnostics/DiagnosticsContentView.swift`).
import SwiftUI

struct DiagnosticsScreen: View {
    var body: some View {
        DiagnosticsContentView()
            .navigationTitle("Diagnostics")
    }
}
