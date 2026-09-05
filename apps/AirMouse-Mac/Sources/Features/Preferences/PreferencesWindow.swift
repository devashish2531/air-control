// Preferences window (assignment brief for this module): General, Pointer, Security, Updates, Advanced.
// Deviation: spec §5.1.3 groups the "Settings" scene's tabs as General/Input/Security/Network; this
// module's assignment specified the General/Pointer/Security/Updates/Advanced grouping used below —
// following the direct task instructions over the tab *names* in §5.1.3 while keeping every underlying
// setting from arch §6.2.
import SwiftUI

struct PreferencesWindow: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            PointerSettingsTab()
                .tabItem { Label("Pointer", systemImage: "cursorarrow") }
            SecuritySettingsTab()
                .tabItem { Label("Security", systemImage: "lock") }
            UpdatesSettingsTab()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AdvancedSettingsTab()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .padding(20)
        .frame(width: 480, height: 360)
        .environment(environment)
    }
}
