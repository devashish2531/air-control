// spec §5.6 "Trusted device store and revocation".
import Foundation
import Observation

@MainActor
@Observable
public final class TrustedDevicesViewModel {
    private let store: any TrustStoring

    public private(set) var devices: [TrustedDeviceRecord] = []
    public var errorMessage: String?
    /// Device id awaiting the "Revoke <name>?" confirmation sheet (spec §5.6).
    public var deviceIDPendingRevoke: String?
    public var isPendingRevokeAll = false

    public init(store: any TrustStoring) {
        self.store = store
    }

    public var deviceNamePendingRevoke: String? {
        guard let id = deviceIDPendingRevoke else { return nil }
        return devices.first(where: { $0.id == id })?.name
    }

    public func refresh() async {
        devices = await store.listDevices()
    }

    public func requestRevoke(id: String) {
        deviceIDPendingRevoke = id
    }

    public func cancelRevoke() {
        deviceIDPendingRevoke = nil
    }

    /// spec §5.6: mark revoked, delete the certificate, close the session within 1 s, release-all, remove
    /// the row. Certificate deletion and session teardown happen inside the real `TrustStore`/`SessionManager`;
    /// this view model only drives the protocol call and updates the table.
    public func confirmRevoke() async {
        guard let id = deviceIDPendingRevoke else { return }
        do {
            try await store.revoke(id: id)
            devices.removeAll { $0.id == id }
        } catch {
            errorMessage = String(describing: error)
        }
        deviceIDPendingRevoke = nil
    }

    public func requestRevokeAll() {
        isPendingRevokeAll = true
    }

    public func cancelRevokeAll() {
        isPendingRevokeAll = false
    }

    public func confirmRevokeAll() async {
        do {
            try await store.revokeAll()
            devices.removeAll()
        } catch {
            errorMessage = String(describing: error)
        }
        isPendingRevokeAll = false
    }

    /// "Allow scripts" checkbox; callers should disable the control when the global toggle is off rather
    /// than calling this (spec §5.6: "disabled with tooltip when the global toggle is off").
    public func setAllowScripts(_ allow: Bool, forDeviceID id: String) async {
        do {
            try await store.setAllowScripts(allow, forDeviceID: id)
            if let index = devices.firstIndex(where: { $0.id == id }) {
                devices[index].allowScripts = allow
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }

    public func rename(id: String, to newName: String) async {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await store.rename(id: id, to: trimmed)
            if let index = devices.firstIndex(where: { $0.id == id }) {
                devices[index].name = trimmed
            }
        } catch {
            errorMessage = String(describing: error)
        }
    }
}
