// docs/08 §5.2 sidebar item 3 "Macros" — embeds the existing macro editor
// (`Features/MacroEditor/MacroEditorContentView.swift`).
import SwiftUI

struct MacrosScreen: View {
    var body: some View {
        MacroEditorContentView()
            .navigationTitle("Macros")
    }
}
