// Shared `Window(id:)` identifiers so `AirMouseHelperApp`'s scenes and every menu action agree on the
// same strings (spec §5.1.3 window list).
public enum WindowID {
    public static let onboarding = "onboarding"
    public static let preferences = "preferences"
    public static let trustedDevices = "trusted-devices"
    public static let diagnostics = "diagnostics"
    public static let pairing = "pairing"
    public static let macroEditor = "macro-editor"
}
