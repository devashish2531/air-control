// Temporary in-memory `TrustStoring` before the real `TrustStore` actor (arch §3.3, Keychain-backed) exists.
// Never touches the Keychain; state is lost on relaunch, which is fine for a UI-shell placeholder.
public actor PlaceholderTrustStore: TrustStoring {
    private var devices: [TrustedDeviceRecord] = []

    public init() {}

    public func listDevices() async -> [TrustedDeviceRecord] { devices }

    public func revoke(id: String) async throws {
        guard devices.contains(where: { $0.id == id }) else { throw TrustStoreError.notFound(id: id) }
        devices.removeAll { $0.id == id }
    }

    public func revokeAll() async throws {
        devices.removeAll()
    }

    public func setAllowScripts(_ allow: Bool, forDeviceID id: String) async throws {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { throw TrustStoreError.notFound(id: id) }
        devices[index].allowScripts = allow
    }

    public func rename(id: String, to newName: String) async throws {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { throw TrustStoreError.notFound(id: id) }
        devices[index].name = newName
    }
}
