// docs/08 §5.2 sidebar item 5 "Settings" — embeds the existing preferences tabs
// (`Features/Preferences/PreferencesContentView.swift`). Also the Cmd-, target (`MenuBarScene`'s
// "Preferences…" button selects this section then opens the main window).
import SwiftUI

struct SettingsScreen: View {
    var body: some View {
        PreferencesContentView()
            .navigationTitle("Settings")
    }
}
