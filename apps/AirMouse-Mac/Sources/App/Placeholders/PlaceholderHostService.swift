// Temporary no-op `HostServing` so the app builds and runs standalone before the networking agent's
// `HostServer` actor (arch §3.3) exists. `AppEnvironment` should be updated to inject the real type once
// it lands; nothing here opens a socket.
import Foundation

public actor PlaceholderHostService: HostServing {
    private var sessions: [ConnectedSessionInfo] = []

    public init() {}

    public func start() async {
        Log.net.info("PlaceholderHostService.start() — no real listener (networking module not wired in yet)")
    }

    public func stop() async {}

    public var connectedSessions: [ConnectedSessionInfo] {
        get async { sessions }
    }

    public func openPairingWindow() async throws -> String {
        "airmouse://pair?placeholder=1"
    }

    public func closePairingWindow() async {}

    public func disconnect(sessionID: String) async {
        sessions.removeAll { $0.id == sessionID }
    }
}
