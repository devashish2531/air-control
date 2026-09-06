// Services/ConnectionManager/ConnectionManager+Environment.swift
// The single DI entry point another agent's `AirControlApp.swift`/`AppEnvironment` wiring needs:
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
import AirControlCrypto

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
    ///
    /// Every identity — reused *or* freshly minted — is proven able to sign before it is handed to
    /// the TLS stack (`KeychainIdentityStore.canSign`, the same probe the Mac helper's host identity
    /// uses). Without that proof a private key that can't produce a signature doesn't fail the
    /// handshake, it *stalls* it: TLS 1.3 sends the client's Certificate only as part of the
    /// Certificate/CertificateVerify/Finished flight, so a `SecKeyCreateSignature` that never
    /// returns leaves the Mac parked in boringssl's `read_client_certificate` state with no alert on
    /// either side until our own 4 s per-candidate watchdog fires. A cheap 2 s probe at startup turns
    /// that invisible stall into "mint a fresh identity", which is always recoverable: the client
    /// certificate is only ever pinned by a Mac we have *already* paired with, and a client whose key
    /// can't sign could never have completed that pairing in the first place.
    @MainActor
    private static func loadOrCreateClientIdentity() -> GeneratedIdentity {
        #if DEBUG
        // On-device diagnosis switch: forces a fresh ephemeral (software-key) client identity every
        // launch, bypassing the Keychain entirely — lets a debug build isolate "is this handshake
        // failure about *this* stored identity/key" from "every identity behaves this way here".
        // Never compiled into a release build.
        if ProcessInfo.processInfo.environment["AIRCONTROL_EPHEMERAL_CLIENT_IDENTITY"] == "1" {
            Log.net.notice("AIRCONTROL_EPHEMERAL_CLIENT_IDENTITY=1: using a fresh ephemeral client identity, bypassing the Keychain")
            Self.identityTrace = "debug-ephemeral"
            return try! IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Client (debug ephemeral)")
        }
        #endif
        let label = KeychainKey.clientIdentityCertificateLabel
        let store = KeychainIdentityStore()
        var trace: [String] = []

        if let existing = try? store.loadIdentity(label: label) {
            let probe = store.signingProbe(existing, timeout: Self.signingProbeTimeout)
            if probe == .usable, let fingerprint = try? Self.fingerprint(of: existing) {
                Log.net.notice("client identity: reused existing Keychain identity")
                Self.identityTrace = (trace + ["reused"]).joined(separator: ",")
                return GeneratedIdentity(secIdentity: existing, certificateDER: Data(), fingerprint: fingerprint, backing: .keychainSecKey, label: label)
            }
            // A stored identity that can't sign is worse than no identity at all (it stalls every
            // handshake, see this function's doc comment). Drop it and mint a replacement.
            Log.net.error("client identity: stored Keychain identity cannot sign (\(probe.summary, privacy: .public)); replacing it")
            trace.append("stale-replaced:\(probe.summary)")
        } else {
            trace.append("absent")
        }

        // Unconditional before minting, not just on the replace path: whatever is under this label is
        // provably unusable (or absent), and leftovers are what made it unusable in the first place —
        // a stray Keychain item (an orphaned certificate, or the public half of an old pair persisted
        // by the pre-fix `IdentityFactory`) can be joined into a bogus `SecIdentity` by a later
        // `kSecClassIdentity` lookup even though a good private key also exists under the same label.
        try? IdentityFactory.deleteIdentity(label: label)

        if let generated = try? IdentityFactory.makeIdentity(
            commonName: "AirControl Client \(UUID().uuidString)",
            label: label,
            // Software key on purpose: on a real iPhone (iOS 26) a Secure Enclave-backed client identity made
            // every mutual-TLS handshake fail before `.ready` (host saw the connect, never a client cert), while
            // the same code path with a software key pairs fine. Revisit if Network.framework gains SE support.
            preferSecureEnclave: false
        ) {
            let probe = store.signingProbe(generated.secIdentity, timeout: Self.signingProbeTimeout)
            if probe == .usable {
                Log.net.notice("client identity: generated a new Keychain-backed identity (\(String(describing: generated.backing), privacy: .public))")
                Self.identityTrace = (trace + ["minted:\(generated.backing)"]).joined(separator: ",")
                return generated
            }
            Log.net.error("client identity: freshly generated Keychain identity cannot sign; falling back")
            trace.append("minted-unusable:\(generated.backing):\(probe.summary)")
            try? IdentityFactory.deleteIdentity(label: label)
        } else {
            trace.append("mint-failed")
        }

        // Sandboxed test/preview hosts without Keychain access: an ephemeral identity keeps the
        // app usable (pairing simply won't persist across relaunch there). Documented to never
        // fail (no Keychain access is required at all), so `try!` is safe here.
        Log.net.notice("client identity: Keychain unavailable, falling back to an ephemeral identity")
        Self.identityTrace = (trace + ["ephemeral"]).joined(separator: ",")
        return try! IdentityFactory.makeEphemeralIdentity(commonName: "AirControl Client (ephemeral)")
    }

    /// How long `loadOrCreateClientIdentity` waits for the throwaway signature that proves an
    /// identity's private key works. Generous enough for a cold Keychain unlock, far short of the
    /// 4 s per-candidate connect budget it exists to protect.
    private static let signingProbeTimeout: TimeInterval = 2.0

    /// How `loadOrCreateClientIdentity` resolved this launch's identity, surfaced by
    /// `RootTabView`'s DEBUG-only `debug.pairingProgress` label — the only diagnostic channel
    /// on-device UI tests have (no root, no OS log access).
    @MainActor public private(set) static var identityTrace = "unset"

    private static func fingerprint(of identity: SecIdentity) throws -> Fingerprint {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        guard status == errSecSuccess, let certificate else {
            throw IdentityFactoryError.identityLookupFailed(status: status)
        }
        return Fingerprint(certificateDER: SecCertificateCopyData(certificate) as Data)
    }
}
