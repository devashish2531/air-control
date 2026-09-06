// docs/08 §5.2 sidebar item 2 "Devices" — embeds the existing Trusted Devices content (list, last
// seen, revoke/forget, rename; `Features/TrustedDevices/TrustedDevicesContentView.swift`).
import SwiftUI

struct DevicesScreen: View {
    var body: some View {
        TrustedDevicesContentView()
            .navigationTitle("Devices")
    }
}
