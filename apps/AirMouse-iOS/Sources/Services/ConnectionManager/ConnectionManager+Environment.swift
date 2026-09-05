// Services/ConnectionManager/ConnectionManager+Environment.swift
// The single DI entry point another agent's `AirMouseApp.swift`/`AppEnvironment` wiring needs:
// build the real `ConnectionManager` plus its four sinks from an `AppEnvironment`, without this
// module editing `AppEnvironment.swift` itself (out of this agent's assigned directories).
//
// Usage the integration point (not this agent's file) is expected to perform once, at app
// launch, before any screen reads `environment.connection`:
// ```swift
// let bundle = ConnectionFeature.make(environment: environment)
// environment.connection = bundle.manager
// environment.pairingRouter = bundle.manager
// ```
// `PairingScreen`/`DevicesScreen` (this agent's own features) don't need that assignment to have
// happened yet for *their own* functionality — they recover `bundle.manager` themselves by
// downcasting `environment.connection as? ConnectionManager`, since a fresh `ConnectionManager` is
// harmless to construct more than once (it only touches the Keychain/DocumentStore, both
// idempotent) — but only one instance should ever be installed into `AppEnvironment` for its
// events/backoff/session state to be singular.

import Foundation
import Security
import AirMouseCrypto

/// Namespace for building this agent's slice of the DI graph.
public enum ConnectionFeature {
    /// Everything `AppEnvironment`'s cross-module slots (`connection`, `pairingRouter`) and the
    /// Touchpad/Motion/Keyboard/Remote features' sinks need.
    public struct Bundle {
        public let manager: ConnectionManager
        public let controlSink: ConnectionControlSink
        public let motionSink: ConnectionMotionSink
        public let keyboardSink: ConnectionKeyboardSink
        public let remoteSink: ConnectionRemoteSink
    }

    /// Builds one `ConnectionManager` (loading/creating the client's own Keychain identity, spec
    /// §3.2.1: "P-256 in Secure Enclave when available") plus its four sinks, wired to `environment`'s
    /// already-constructed `documentStore`/`userSettings`/`diagnostics`/`idleTimer`/`haptics`.
    @MainActor
    public static func make(environment: AppEnvironment) -> Bundle {
        let identity = Self.loadOrCreateClientIdentity()
        let knownHosts = KnownHostsStore(documentStore: environment.documentStore)
        let manager = ConnectionManager(
            knownHosts: knownHosts,
            userSettings: environment.userSettings,
            diagnostics: environment.diagnostics,
            idleTimer: environment.idleTimer,
            haptics: environment.haptics,
            clock: SystemClock(),
            clientIdentity: identity
        )
        return Bundle(
            manager: manager,
            controlSink: ConnectionControlSink(manager: manager),
            motionSink: ConnectionMotionSink(manager: manager),
            keyboardSink: ConnectionKeyboardSink(manager: manager),
            remoteSink: ConnectionRemoteSink(manager: manager)
        )
    }

    /// spec §3.2.1: client key "P-256 in Secure Enclave when available, else Keychain",
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (the `IdentityFactory.makeIdentity`
    /// default). Looked up by `KeychainKey.clientIdentityCertificateLabel` first so a relaunch
    /// reuses the same identity/fingerprint rather than re-pairing.
    private static func loadOrCreateClientIdentity() -> GeneratedIdentity {
        let label = KeychainKey.clientIdentityCertificateLabel
        let store = KeychainIdentityStore()
        if let existing = try? store.loadIdentity(label: label),
           let fingerprint = try? Self.fingerprint(of: existing) {
            return GeneratedIdentity(secIdentity: existing, certificateDER: Data(), fingerprint: fingerprint, backing: .keychainSecKey, label: label)
        }
        if let generated = try? IdentityFactory.makeIdentity(
            commonName: "AirMouse Client \(UUID().uuidString)",
            label: label,
            // Software key on purpose: on a real iPhone (iOS 26) a Secure Enclave-backed client identity made
            // every mutual-TLS handshake fail before `.ready` (host saw the connect, never a client cert), while
            // the same code path with a software key pairs fine. Revisit if Network.framework gains SE support.
            preferSecureEnclave: false
        ) {
            return generated
        }
        // Sandboxed test/preview hosts without Keychain access: an ephemeral identity keeps the
        // app usable (pairing simply won't persist across relaunch there). Documented to never
        // fail (no Keychain access is required at all), so `try!` is safe here.
        return try! IdentityFactory.makeEphemeralIdentity(commonName: "AirMouse Client (ephemeral)")
    }

    private static func fingerprint(of identity: SecIdentity) throws -> Fingerprint {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw IdentityFactoryError.identityLookupFailed(status: status)
        }
        return Fingerprint(certificateDER: SecCertificateCopyData(certificate) as Data)
    }
}
