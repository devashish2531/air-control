// spec §5.1.3 "Diagnostics" window; arch §8 "Diagnostics HUD" (Mac side, 4 Hz).
import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class DiagnosticsViewModel {
    private let sink: any DiagnosticsSink
    public private(set) var snapshot: DiagnosticsSnapshot = .empty
    // `nonisolated(unsafe)`: only touched from start/stopPolling and deinit (nonisolated per Swift's
    // default class-deinit rules).
    nonisolated(unsafe) private var pollTask: Task<Void, Never>?

    public init(sink: any DiagnosticsSink) {
        self.sink = sink
    }

    public func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: .milliseconds(250)) // 4 Hz, arch §8
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() async {
        snapshot = await sink.snapshot
    }

    /// "Export diagnostics…"/"Copy diagnostics report": counters and timing only, never uploaded
    /// (spec §5.1.3, §7.4 NFR-PRIV-005). Copies redacted JSON to the pasteboard.
    public func copyDiagnosticsReport() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(json, forType: .string)
    }

    deinit {
        pollTask?.cancel()
    }
}
