// spec §5.5.3: "Shortcut picker (`/usr/bin/shortcuts list`, cached 60 s)". A pure listing helper for
// the editor's UI — not policy-gated (unlike actually *running* a Shortcut, which goes through
// `MacroEngine`'s §5.5.5 gate) since it has no side effects on the user's system.
import Foundation

/// Caches the output of `/usr/bin/shortcuts list` for 60 s so re-opening the Shortcut name field's
/// picker doesn't re-spawn the process on every keystroke.
public actor ShortcutsCatalog {
    public static let shared = ShortcutsCatalog()

    private var cachedNames: [String]?
    private var cachedAt: ContinuousClock.Instant?
    private let cacheLifetime: Duration = .seconds(60)
    private let scriptRunner: ScriptRunner

    public init(scriptRunner: ScriptRunner = ScriptRunner()) {
        self.scriptRunner = scriptRunner
    }

    public func names() async -> [String] {
        if let cachedNames, let cachedAt, ContinuousClock.now - cachedAt < cacheLifetime {
            return cachedNames
        }
        let result = await scriptRunner.run(
            executable: "/usr/bin/shortcuts",
            arguments: ["list"],
            environment: DefaultMacroActionExecutor.reducedEnvironment(),
            timeout: .seconds(10)
        )
        let names = result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        cachedNames = names
        cachedAt = .now
        return names
    }
}
