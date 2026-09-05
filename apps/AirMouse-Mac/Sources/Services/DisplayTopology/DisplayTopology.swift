// arch §3.3 — "HSO ... displays" input to HostStateObserver; DisplayClamp (owned by the injection agent)
// reads the resulting `DisplayTopologySnapshot` off the main actor via HostStateObserver.
import AppKit
import CoreGraphics
import Observation

/// Live view of the Mac's connected displays, refreshed on `NSApplication.didChangeScreenParametersNotification`.
@MainActor
@Observable
public final class DisplayTopology {
    public private(set) var snapshot: DisplayTopologySnapshot
    private let listProvider: @MainActor () -> [DisplayInfo]
    // Only touched from init/deinit, both on the main actor in practice; needed so `deinit`
    // (nonisolated per Swift's default class-deinit rules) can remove the observer.
    // `@ObservationIgnored` keeps the `@Observable` macro from re-wrapping storage access in a
    // way that would otherwise make `nonisolated(unsafe)` a no-op on this property.
    @ObservationIgnored
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    public init(listProvider: @escaping @MainActor () -> [DisplayInfo] = DisplayTopology.currentDisplays) {
        self.listProvider = listProvider
        snapshot = DisplayTopologySnapshot.make(from: listProvider())
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // `queue: .main` guarantees this runs on the main thread/actor already.
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
    }

    public func refresh() {
        snapshot = DisplayTopologySnapshot.make(from: listProvider())
    }

    /// Queries the live display list via `CGGetActiveDisplayList` / `CGDisplayBounds`.
    public static func currentDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let mainID = CGMainDisplayID()
        return ids.prefix(Int(count)).map { id in
            DisplayInfo(id: id, bounds: CGDisplayBounds(id), isMain: id == mainID)
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
