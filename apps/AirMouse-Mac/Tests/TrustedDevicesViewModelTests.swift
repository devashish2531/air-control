import Testing
@testable import Air_Mouse

@MainActor
@Suite struct TrustedDevicesViewModelTests {
    @Test func refreshLoadsDevicesFromTheStore() async {
        let store = MockTrustStore(devices: [.fixture(id: "a"), .fixture(id: "b")])
        let viewModel = TrustedDevicesViewModel(store: store)

        await viewModel.refresh()

        #expect(viewModel.devices.count == 2)
    }

    @Test func revokeRequiresConfirmationBeforeCallingTheStore() async {
        let store = MockTrustStore(devices: [.fixture(id: "a")])
        let viewModel = TrustedDevicesViewModel(store: store)
        await viewModel.refresh()

        viewModel.requestRevoke(id: "a")
        #expect(viewModel.deviceIDPendingRevoke == "a")
        #expect(viewModel.deviceNamePendingRevoke == "Dev's iPhone")
        #expect(await store.revokedIDs.isEmpty)

        await viewModel.confirmRevoke()

        #expect(viewModel.devices.isEmpty)
        #expect(await store.revokedIDs == ["a"])
        #expect(viewModel.deviceIDPendingRevoke == nil)
    }

    @Test func cancelRevokeLeavesTheDeviceInPlace() async {
        let store = MockTrustStore(devices: [.fixture(id: "a")])
        let viewModel = TrustedDevicesViewModel(store: store)
        await viewModel.refresh()

        viewModel.requestRevoke(id: "a")
        viewModel.cancelRevoke()

        #expect(viewModel.deviceIDPendingRevoke == nil)
        #expect(viewModel.devices.count == 1)
        #expect(await store.revokedIDs.isEmpty)
    }

    @Test func revokeFailureSurfacesAnErrorAndKeepsTheRow() async {
        let store = MockTrustStore(devices: [.fixture(id: "a")])
        await store.setShouldFailRevoke(true)
        let viewModel = TrustedDevicesViewModel(store: store)
        await viewModel.refresh()

        viewModel.requestRevoke(id: "a")
        await viewModel.confirmRevoke()

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.devices.count == 1)
    }

    @Test func revokeAllClearsEveryRow() async {
        let store = MockTrustStore(devices: [.fixture(id: "a"), .fixture(id: "b")])
        let viewModel = TrustedDevicesViewModel(store: store)
        await viewModel.refresh()

        viewModel.requestRevokeAll()
        await viewModel.confirmRevokeAll()

        #expect(viewModel.devices.isEmpty)
        #expect(await store.revokeAllCallCount == 1)
        #expect(viewModel.isPendingRevokeAll == false)
    }

    @Test func renameUpdatesTheLocalRowOnSuccess() async {
        let store = MockTrustStore(devices: [.fixture(id: "a", name: "Old Name")])
        let viewModel = TrustedDevicesViewModel(store: store)
        await viewModel.refresh()

        await viewModel.rename(id: "a", to: "New Name")

        #expect(viewModel.devices.first?.name == "New Name")
    }

    @Test func setAllowScriptsUpdatesTheLocalRow() async {
        let store = MockTrustStore(devices: [.fixture(id: "a", allowScripts: false)])
        let viewModel = TrustedDevicesViewModel(store: store)
        await viewModel.refresh()

        await viewModel.setAllowScripts(true, forDeviceID: "a")

        #expect(viewModel.devices.first?.allowScripts == true)
    }
}

private extension MockTrustStore {
    func setShouldFailRevoke(_ value: Bool) {
        shouldFailRevoke = value
    }
}
