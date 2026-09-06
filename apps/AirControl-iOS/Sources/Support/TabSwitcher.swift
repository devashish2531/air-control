// Support/TabSwitcher.swift
// docs/08 §2.2 — lets features that cover the root tab bar (the Keyboard tab's input accessory
// bar) switch tabs or open Settings without owning `RootTabView`'s state. `RootTabView` injects
// the live value; the default is a no-op so previews and tests work without the shell.

import SwiftUI

public struct TabSwitcher: Sendable {
    public var switchTo: @MainActor @Sendable (AppTab) -> Void
    public var openSettings: @MainActor @Sendable () -> Void

    public init(
        switchTo: @escaping @MainActor @Sendable (AppTab) -> Void,
        openSettings: @escaping @MainActor @Sendable () -> Void
    ) {
        self.switchTo = switchTo
        self.openSettings = openSettings
    }

    public static let noop = TabSwitcher(switchTo: { _ in }, openSettings: {})
}

public extension EnvironmentValues {
    @Entry var tabSwitcher: TabSwitcher = .noop
}
