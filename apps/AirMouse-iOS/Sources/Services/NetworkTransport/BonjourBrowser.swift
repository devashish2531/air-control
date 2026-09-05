// Services/NetworkTransport/BonjourBrowser.swift
// Client-side Bonjour discovery — spec §3.1 (Discovery), §4.5.3 (Browsing): "browses only
// `_airmouse._tcp`", "`includePeerToPeer = false`", "results debounced 100 ms", cross-talk guard
// R-10 ("a browse result whose TXT lacks `v` or whose `v` list does not include a version the
// client speaks is hidden from the Devices list").

import Foundation
import Network
import AirMouseProtocol

/// One Mac visible on the local network, parsed from a live `NWBrowser.Result` + its TXT record
/// (spec §3.1.2). Not `Sendable`-unsafe: `endpoint` is Network.framework's own `NWEndpoint`
/// (`Sendable`), and everything else is value data.
///
/// This is `NetworkTransport`'s own model — `AirMouseCore`/`AirMouseProtocol` know `TXTRecord` but
/// have no notion of "a thing currently visible on the network" (that is inherently a `Network`
/// concept, arch §3.1: Core never imports `Network`).
public struct DiscoveredHost: Sendable, Identifiable, Equatable {
    /// The TXT `id` (host ID), b64u-decoded — stable per Mac install, used to match a
    /// `TrustedDeviceRecord`/known-host entry independent of display name or address.
    public var id: Data
    public var name: String
    public var machineModel: String
    /// First 16 bytes of the host certificate FP (a hint only, spec §3.1.2 — trust is still
    /// decided by the full pinned certificate during TLS).
    public var fingerprintPrefix: Data
    public var tcpPort: Int
    public var udpPort: Int
    public var supportedVersions: [Int]
    /// The live Bonjour endpoint — feed straight into `NWControlChannel.connect(to:...)` so
    /// `Network.framework` resolves and connects in one step (spec §3.3.2 candidate tier 1).
    public var endpoint: NWEndpoint

    public init(
        id: Data,
        name: String,
        machineModel: String,
        fingerprintPrefix: Data,
        tcpPort: Int,
        udpPort: Int,
        supportedVersions: [Int],
        endpoint: NWEndpoint
    ) {
        self.id = id
        self.name = name
        self.machineModel = machineModel
        self.fingerprintPrefix = fingerprintPrefix
        self.tcpPort = tcpPort
        self.udpPort = udpPort
        self.supportedVersions = supportedVersions
        self.endpoint = endpoint
    }

    public static func == (lhs: DiscoveredHost, rhs: DiscoveredHost) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.tcpPort == rhs.tcpPort && lhs.udpPort == rhs.udpPort
    }
}

/// Browses `_airmouse._tcp` and publishes the current result set as `DiscoveredHost` snapshots.
/// One instance per "Devices visible or auto-connect pending" window (spec §4.5.3); callers
/// `start()`/`stop()` it to match that lifecycle rather than running it for the app's whole life.
public final class BonjourBrowser: @unchecked Sendable {
    public enum BrowseState: Sendable, Equatable {
        case idle
        case browsing
        case localNetworkDenied
        case failed(String)
    }

    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.airmouse.app.net.browser")

    public let hosts: AsyncStream<[DiscoveredHost]>
    private let hostsContinuation: AsyncStream<[DiscoveredHost]>.Continuation
    public let state: AsyncStream<BrowseState>
    private let stateContinuation: AsyncStream<BrowseState>.Continuation

    public init() {
        var hostsContinuation: AsyncStream<[DiscoveredHost]>.Continuation!
        self.hosts = AsyncStream { hostsContinuation = $0 }
        self.hostsContinuation = hostsContinuation
        var stateContinuation: AsyncStream<BrowseState>.Continuation!
        self.state = AsyncStream { stateContinuation = $0 }
        self.stateContinuation = stateContinuation
    }

    /// Starts (or restarts) browsing. Safe to call repeatedly; stops any prior browser first.
    public func start() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = false // spec §3.1.1: "no AWDL".
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: BonjourServiceType.control, domain: nil), using: parameters)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] browserState in
            guard let self else { return }
            switch browserState {
            case .ready:
                self.stateContinuation.yield(.browsing)
            case .waiting(let error):
                if Self.isLocalNetworkDenied(error) {
                    self.stateContinuation.yield(.localNetworkDenied)
                }
            case .failed(let error):
                self.stateContinuation.yield(.failed(String(describing: error)))
            case .cancelled:
                self.stateContinuation.yield(.idle)
            case .setup:
                break
            @unknown default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            let hosts = results.compactMap(Self.discoveredHost(from:))
            self.hostsContinuation.yield(hosts)
        }
        browser.start(queue: queue)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }

    private static func discoveredHost(from result: NWBrowser.Result) -> DiscoveredHost? {
        guard case .bonjour(let txtRecord) = result.metadata else { return nil }
        return discoveredHost(txtDictionary: txtRecord.dictionary, endpoint: result.endpoint)
    }

    /// The pure TXT-parsing half of `discoveredHost(from:)`, split out so it's testable without
    /// an `NWBrowser.Result` (which has no public initializer — a live browse is the only way to
    /// produce one). `endpoint` is any `NWEndpoint` — tests pass a literal `.hostPort(...)`.
    ///
    /// R-10 cross-talk guard (spec §3.1.1): "a browse result whose TXT lacks `v` or whose `v`
    /// list does not include a version the client speaks is hidden from the Devices list."
    static func discoveredHost(txtDictionary: [String: String], endpoint: NWEndpoint) -> DiscoveredHost? {
        guard let parsed = try? TXTRecord(parsing: txtDictionary),
              parsed.supportsVersion(ProtocolConstants.protocolVersion) else {
            return nil
        }
        return DiscoveredHost(
            id: parsed.hostID,
            name: parsed.hostName,
            machineModel: parsed.machineModel,
            fingerprintPrefix: parsed.fingerprintPrefix,
            tcpPort: parsed.tcpPort,
            udpPort: parsed.udpPort,
            supportedVersions: parsed.supportedVersions,
            endpoint: endpoint
        )
    }

    private static func isLocalNetworkDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error, code == -65570 { return true } // kDNSServiceErr_PolicyDenied
        return false
    }
}
