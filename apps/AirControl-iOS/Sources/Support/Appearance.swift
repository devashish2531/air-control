// Support/Appearance.swift
// docs/08 §4: maps the persisted `AppearanceMode` (Services/DocumentStore/UserSettings.swift) to
// the `ColorScheme?` SwiftUI actually wants for `.preferredColorScheme` — `.system` means "follow
// the device", i.e. `nil`, not a scheme. The shell agent applies this at the root
// (`RootTabView.swift`: `.preferredColorScheme(environment.userSettings.snapshot.appearance.mode.colorScheme)`).
//
// DEVIATION from this task's literal wording ("extension AppearanceSetting"): the type that
// actually exists in `UserSettings.swift` is `AppearanceMode` (light/dark/system) — there is no
// `AppearanceSetting` type in the codebase. Extending the real type here; flagged in the final
// report.

import SwiftUI

extension AppearanceMode {
    /// `.system` → `nil` so `.preferredColorScheme(nil)` lets the device/app follow the OS setting.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
