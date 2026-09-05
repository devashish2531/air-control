// Commands/Pair.swift
// `airmouse-cli pair <airmouse://pair?...>` — first-time pairing (spec §3.2.2): parse the QR/manual
// URL, open a TLS connection pinned to its `fp`, run `ClientSession.pair(url:)`, then save the host as
// trusted so later `connect`/`move`/etc. can reconnect without re-scanning.
import AirMouseCore
import AirMouseCrypto
import AirMouseProtocol
import ArgumentParser
import Foundation

struct Pair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Pair with a host using a scanned/typed airmouse://pair URL."
    )

    @Argument(help: "The airmouse://pair?... URL (from the host's pairing QR/window).")
    var url: String

    @Flag(help: "Print the result as JSON.")
    var json: Bool = false

    @Flag(help: "Log verbose diagnostic output to stderr.")
    var verbose: Bool = false

    func run() async throws {
        let pairingURL: PairingURL
        do {
            pairingURL = try PairingClient.parse(url)
        } catch {
            throw CLIError("not a valid pairing URL: \(error)")
        }
        guard let pinnedFingerprint = Fingerprint(bytes: Array(pairingURL.fingerprint)) else {
            throw CLIError("pairing URL fingerprint is not 32 bytes")
        }
        guard let address = pairingURL.addresses.first else {
            throw CLIError("pairing URL has no candidate addresses")
        }

        let (session, control, _) = try await CLIRuntime.openSession(
            host: address,
            controlPort: pairingURL.tcpPort,
            pinnedFingerprint: pinnedFingerprint,
            verbose: verbose
        )

        let info: ConnectedInfo
        do {
            info = try await session.pair(url: pairingURL)
        } catch {
            await control.close()
            throw CLIError("pairing failed: \(error)")
        }

        try? CLIStore.saveTrustedHost(TrustedHostRecord(
            hostIDB64u: info.host.id.data.b64u,
            name: info.host.name,
            fingerprintHex: pinnedFingerprint.hexString,
            address: address,
            tcpPort: pairingURL.tcpPort,
            udpPort: pairingURL.udpPort,
            pairedAt: Date()
        ))

        if json {
            let payload: [String: Any] = [
                "host": info.host.name,
                "model": info.host.model,
                "fingerprint": pinnedFingerprint.hexString,
                "address": address,
                "tcpPort": pairingURL.tcpPort,
                "udpPort": info.udpPort,
                "protocolVersion": info.protocolVersion,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("Paired with \(info.host.name) (\(info.host.model)) at \(address):\(pairingURL.tcpPort)")
            print("fingerprint: \(pinnedFingerprint.hexString)")
        }

        await session.close(reason: .userQuit)
    }
}
