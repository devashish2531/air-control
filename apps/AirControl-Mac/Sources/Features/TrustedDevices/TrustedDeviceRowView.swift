// spec §5.6 table columns: Name (editable), Model, OS, First paired, Last seen, Allow scripts, Revoke.
import SwiftUI

struct TrustedDeviceRowView: View {
    let device: TrustedDeviceRecord
    let allowScriptsGloballyEnabled: Bool
    let onRename: (String) -> Void
    let onAllowScriptsChanged: (Bool) -> Void
    let onRevoke: () -> Void

    @State private var nameDraft: String

    init(
        device: TrustedDeviceRecord,
        allowScriptsGloballyEnabled: Bool,
        onRename: @escaping (String) -> Void,
        onAllowScriptsChanged: @escaping (Bool) -> Void,
        onRevoke: @escaping () -> Void
    ) {
        self.device = device
        self.allowScriptsGloballyEnabled = allowScriptsGloballyEnabled
        self.onRename = onRename
        self.onAllowScriptsChanged = onAllowScriptsChanged
        self.onRevoke = onRevoke
        _nameDraft = State(initialValue: device.name)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $nameDraft)
                .textFieldStyle(.plain)
                .onSubmit { onRename(nameDraft) }
                .frame(minWidth: 120, alignment: .leading)
                .accessibilityLabel("Device name")

            Text(device.model)
                .frame(minWidth: 100, alignment: .leading)
            Text(device.osVersion)
                .frame(minWidth: 70, alignment: .leading)
            Text(device.firstPaired, style: .date)
                .frame(minWidth: 90, alignment: .leading)
            Text(device.lastSeen, style: .relative)
                .frame(minWidth: 90, alignment: .leading)

            Toggle("Allow scripts", isOn: Binding(
                get: { device.allowScripts },
                set: { onAllowScriptsChanged($0) }
            ))
            .labelsHidden()
            .disabled(!allowScriptsGloballyEnabled)
            .help(allowScriptsGloballyEnabled ? "Allow this device to run script macros" : "Script macros are off globally (Settings › Security)")

            Button("Revoke", role: .destructive, action: onRevoke)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(device.name), \(device.model)")
    }
}
