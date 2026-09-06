// Tests/AppearanceTests.swift
// docs/08 §4: `AppearanceMode.colorScheme` — `.system` must map to `nil` so
// `.preferredColorScheme(nil)` lets the app follow the device setting; `.light`/`.dark` map
// straight through.

import SwiftUI
import Testing
@testable import Air_Mouse

@Suite struct AppearanceTests {
    @Test func systemMapsToNilColorScheme() {
        #expect(AppearanceMode.system.colorScheme == nil)
    }

    @Test func lightMapsToLightColorScheme() {
        #expect(AppearanceMode.light.colorScheme == .light)
    }

    @Test func darkMapsToDarkColorScheme() {
        #expect(AppearanceMode.dark.colorScheme == .dark)
    }
}
