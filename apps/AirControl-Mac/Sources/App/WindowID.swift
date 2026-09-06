// Shared `Window(id:)` identifiers so `AirControlHelperApp`'s scenes and every menu action agree on the
// same strings (spec §5.1.3 window list; docs/08 §5.2 collapses the pairing/trusted-devices/
// diagnostics/macro-editor/preferences windows into sections of the single `main` window).
public enum WindowID {
    public static let onboarding = "onboarding"
    /// docs/08 §5.1/§5.2: the single `NavigationSplitView` main window ("Air Control"). Deep-linked
    /// into a sidebar section via `MainWindowRouter` rather than a dedicated `Window(id:)` per screen.
    public static let main = "main"
}
