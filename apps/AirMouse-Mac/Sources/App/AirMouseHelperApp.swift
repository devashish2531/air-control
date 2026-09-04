import SwiftUI

@main
struct AirMouseHelperApp: App {
    var body: some Scene {
        MenuBarExtra("Air Mouse", systemImage: "cursorarrow.motionlines") {
            Text("Air Mouse")
            Divider()
            Button("Quit Air Mouse") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
