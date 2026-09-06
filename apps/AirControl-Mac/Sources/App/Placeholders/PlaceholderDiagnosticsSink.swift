// Temporary empty `DiagnosticsSink` before the net/inject executors (owned by other agents) publish a
// real `DiagnosticsSnapshot` (arch §8).
public actor PlaceholderDiagnosticsSink: DiagnosticsSink {
    public init() {}

    public var snapshot: DiagnosticsSnapshot {
        get async { .empty }
    }
}
