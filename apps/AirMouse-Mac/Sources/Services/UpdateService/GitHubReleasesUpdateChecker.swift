// spec §5.7.2 — interim, opt-in "is there a newer tag" check with no download. Real releases still ship
// as before; this only tells the user one exists. // TODO(M8): Sparkle (see UpdateService.swift).
import Foundation

public struct GitHubReleasesUpdateChecker: UpdateService {
    public let owner: String
    public let repo: String
    public let currentVersion: String
    private let urlSession: URLSession

    public init(owner: String, repo: String, currentVersion: String, urlSession: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.currentVersion = currentVersion
        self.urlSession = urlSession
    }

    public func checkForUpdates() async throws -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            return UpdateCheckResult(currentVersion: currentVersion, latestVersion: nil, isNewerAvailable: false, releaseURL: nil)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, _) = try await urlSession.data(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let tag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let isNewer = Self.isVersion(tag, newerThan: currentVersion)
        return UpdateCheckResult(
            currentVersion: currentVersion,
            latestVersion: tag,
            isNewerAvailable: isNewer,
            releaseURL: release.htmlURL
        )
    }

    /// Dotted-integer semver-ish comparison; unparsable components compare as 0 rather than throwing, so a
    /// malformed tag never crashes the (opt-in, best-effort) update check.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let a = parts(candidate)
        let b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
