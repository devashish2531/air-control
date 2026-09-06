// docs/08 §5.2: "Sidebar shows a live status dot next to 'Overview' (same colours as iOS §2.1)."
// iOS's `ConnectionStatusDot` (docs/08 §2.1) has four states (green/amber-pulsing/grey/red); the Mac
// side only has a "device connected" boolean and a "server running" boolean to work from (no
// per-connection "connecting/reconnecting" phase is exposed through `HostServing`, spec §5.1's
// intentionally tiny surface), so this reuses the same three-colour subset the iOS dot's non-pulsing
// states use and omits the amber "connecting" phase — noted as a deviation in this module's report.
import SwiftUI

struct ConnectionStatusDot: View {
    enum State {
        /// At least one device connected.
        case connected
        /// Server listening, no device connected yet.
        case idle
        /// Server not running (stopped, still starting, or failed to bind).
        case error
    }

    let state: State

    private var color: Color {
        switch state {
        case .connected: .green
        case .idle: .gray
        case .error: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}
