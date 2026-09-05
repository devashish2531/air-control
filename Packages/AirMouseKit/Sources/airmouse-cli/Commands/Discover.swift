// Commands/Discover.swift
// `airmouse-cli discover` — browses `_airmouse._tcp` (spec §3.1.1: "the client browses only
// `_airmouse._tcp`... `includePeerToPeer = false`") and prints each result's TXT record (spec §3.1.2).
import AirMouseProtocol
import ArgumentParser
import Foundation
import Network

struct Discover: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Browse the local network for Air Mouse hosts (Bonjour _airmouse._tcp)."
    )

    @Option(help: "Seconds to browse before printing results.")
    var timeout: Double = 3

    @Flag(help: "Print results as JSON.")
    var json: Bool = false

    func run() async throws {
        let browseParameters = NWParameters()
        browseParameters.includePeerToPeer = false // spec §3.1.1: "includePeerToPeer = false on both sides (no AWDL)"
        let browser = NWBrowser(
            for: .bonjour(type: BonjourServiceType.control, domain: BonjourServiceType.domain),
            using: browseParameters
        )
        let box = ResultsBox()
        browser.browseResultsChangedHandler = { results, _ in
            box.results = Array(results)
        }
        browser.start(queue: .main)
        try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
        browser.cancel()

        let records = box.results.compactMap(DiscoveredHost.init)
        if json {
            let data = try JSONEncoder().encode(records)
            print(String(data: data, encoding: .utf8) ?? "[]")
        } else if records.isEmpty {
            print("No Air Mouse hosts found in \(timeout)s.")
        } else {
            for record in records {
                print("\(record.name)  id=\(record.hostID)  fp=\(record.fingerprintPrefix)…  endpoints=\(record.endpoints.joined(separator: ","))  tcp=\(record.tcpPort) udp=\(record.udpPort)")
            }
        }
    }
}

/// `NWBrowser.Result` is not `Sendable`/copyable across the browse handler's queue reliably in all
/// SDKs; snapshotting into `[NWBrowser.Result]` on `.main` and reading it back after `cancel()`
/// avoids any concurrency hazard here (this command has no long-running receive loop to race with).
private final class ResultsBox: @unchecked Sendable {
    var results: [NWBrowser.Result] = []
}

private struct DiscoveredHost: Codable {
    var name: String
    var hostID: String
    var fingerprintPrefix: String
    var tcpPort: Int
    var udpPort: Int
    var endpoints: [String]

    init?(result: NWBrowser.Result) {
        guard case .service(let serviceName, _, _, _) = result.endpoint else { return nil }
        guard case .bonjour(let txt) = result.metadata else { return nil }
        var dict: [String: String] = [:]
        for (key, value) in txt.dictionary {
            dict[key] = value
        }
        guard let record = try? TXTRecord(parsing: dict) else { return nil }
        self.name = serviceName
        self.hostID = record.hostID.b64u
        self.fingerprintPrefix = record.fingerprintPrefix.map { String(format: "%02x", $0) }.joined()
        self.tcpPort = record.tcpPort
        self.udpPort = record.udpPort
        self.endpoints = [String(describing: result.endpoint)]
    }
}
