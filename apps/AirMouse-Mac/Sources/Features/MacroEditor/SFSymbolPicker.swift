// spec §5.5.3: "Icon (searchable SF Symbol picker with preview)". `MacroValidator` (AirMouseProtocol,
// Foundation-only) can't check symbol validity itself (no UIKit/SwiftUI symbol catalog) — spec §5.5.1
// puts that check on "the validating OS", i.e. here, via `NSImage(systemSymbolName:)`.
import AppKit
import SwiftUI

/// A curated grid of common SF Symbols (spec: "curated list + free text") plus a text field for any
/// other symbol name, validated live against `NSImage(systemSymbolName:accessibilityDescription:)` —
/// spec §5.5.1's documented fallback for an icon that isn't a known symbol on this OS is to render as
/// `command`, so an invalid free-text entry is flagged rather than silently rejected.
struct SFSymbolPicker: View {
    @Binding var symbolName: String

    @State private var searchText = ""

    /// Small, curated set covering the starter macros (spec §5.5.2) plus common macro use cases
    /// (window management, media, apps, text/dev). Not exhaustive — free text covers the rest.
    static let curated: [String] = [
        "command", "keyboard", "square.grid.3x3.fill", "menubar.dock.rectangle", "camera.viewfinder",
        "lock.fill", "magnifyingglass", "terminal.fill", "safari.fill", "music.note", "play.fill",
        "pause.fill", "forward.fill", "backward.fill", "speaker.wave.2.fill", "speaker.slash.fill",
        "sun.max.fill", "moon.fill", "wifi", "bolt.fill", "gearshape.fill", "folder.fill", "doc.fill",
        "trash.fill", "star.fill", "heart.fill", "bell.fill", "envelope.fill", "calendar",
        "message.fill", "phone.fill", "video.fill", "photo.fill", "printer.fill", "airplayaudio",
        "arrow.clockwise", "arrow.counterclockwise", "arrow.up.left.and.arrow.down.right",
        "rectangle.on.rectangle", "macwindow", "display", "externaldrive.fill", "network",
        "paintbrush.fill", "hammer.fill", "wrench.and.screwdriver.fill", "flask.fill", "bookmark.fill",
    ]

    private var filtered: [String] {
        guard !searchText.isEmpty else { return Self.curated }
        return Self.curated.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var isKnownSymbol: Bool {
        !symbolName.isEmpty && NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isKnownSymbol ? symbolName : "questionmark.square.dashed")
                    .font(.title2)
                    .frame(width: 28, height: 28)
                TextField("SF Symbol name", text: $symbolName)
                    .textFieldStyle(.roundedBorder)
                if !isKnownSymbol {
                    Label("Unknown symbol — shown as \"command\"", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            TextField("Search curated icons", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 8)], spacing: 8) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            symbolName = name
                        } label: {
                            Image(systemName: name)
                                .frame(width: 28, height: 28)
                                .background(name == symbolName ? Color.accentColor.opacity(0.25) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 120)
        }
    }
}
