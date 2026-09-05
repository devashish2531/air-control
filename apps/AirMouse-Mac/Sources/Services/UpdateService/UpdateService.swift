// spec §5.7.2 "Update checking" and §7.5 "update check off" by default.
// TODO(M8): Sparkle. Replace the GitHubReleasesUpdateChecker stub with SPUStandardUpdaterController
// (EdDSA-signed appcast, `SUAutomaticallyUpdate = NO`) once Sparkle is added as a dependency in
// project.yml — that file is out of scope for this module, so Sparkle is intentionally not wired in yet.
import Foundation

/// What a Homebrew-cask install disables in favor of the `brew upgrade` hint (spec §5.7.2, §9 E-MAC-UPDATE-BREW).
public enum InstallSource: Sendable, Equatable {
    case direct
    case homebrewCask

    public static func detect(bundlePath: String = Bundle.main.bundlePath) -> InstallSource {
        bundlePath.contains("/Caskroom/") ? .homebrewCask : .direct
    }
}

public struct UpdateCheckResult: Sendable, Equatable {
    public var currentVersion: String
    public var latestVersion: String?
    public var isNewerAvailable: Bool
    public var releaseURL: URL?

    public init(currentVersion: String, latestVersion: String?, isNewerAvailable: Bool, releaseURL: URL?) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.isNewerAvailable = isNewerAvailable
        self.releaseURL = releaseURL
    }
}

/// Minimal update-checking surface the UI shell needs. Opt-in only (spec §5.7.2); this is the only
/// non-LAN network access the helper makes (NFR-SEC-006), so implementations must not touch anything
/// beyond the release-listing endpoint.
public protocol UpdateService: Sendable {
    func checkForUpdates() async throws -> UpdateCheckResult
}
