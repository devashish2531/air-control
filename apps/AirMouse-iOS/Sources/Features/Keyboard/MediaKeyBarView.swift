// Features/Keyboard/MediaKeyBarView.swift
// Media key bar (this agent's assignment: "play/pause, prev, next, vol -, vol +, mute,
// brightness"; spec §4.4.5: "Media buttons send `mediaKey{key, tap}`; volume up/down hold → down/
// up for host repeat"). Previous/Next/Play-Pause/Mute are single taps; Volume/Brightness up/down
// repeat while held (`KeyboardViewModel.beginMediaKeyRepeat`/`endMediaKeyRepeat`).
//
// Every button draws its own fixed-size background (a plain `Button` label, never
// `.buttonStyle(.bordered)`) so its visible bounds match its 44×44 tap target exactly — the
// system bordered/"glass" button style pads its chrome well past the label's frame, which at the
// 8 pt spacing this row uses made consecutive circular transport buttons visually overlap. Fills
// use the same semantic tokens as `KeyCapButton.swift` (docs/08 §3.1) so this row matches the rest
// of the tab in both themes.

import SwiftUI
import AirMouseProtocol

struct MediaKeyBarView: View {
    let viewModel: KeyboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Media", comment: "Keyboard screen: media key bar section header")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            AdaptiveKeyRow(spacing: 8) {
                tapButton(.previous, symbol: "backward.end.fill", label: String(localized: "Previous", comment: "Keyboard media bar: Previous track button"))
                tapButton(.playPause, symbol: "playpause.fill", label: String(localized: "Play or Pause", comment: "Keyboard media bar: Play/Pause button"))
                tapButton(.next, symbol: "forward.end.fill", label: String(localized: "Next", comment: "Keyboard media bar: Next track button"))
                tapButton(.mute, symbol: "speaker.slash.fill", label: String(localized: "Mute", comment: "Keyboard media bar: Mute button"))
                holdButton(.volumeDown, symbol: "speaker.wave.1.fill", label: String(localized: "Volume down", comment: "Keyboard media bar: Volume down button"))
                holdButton(.volumeUp, symbol: "speaker.wave.3.fill", label: String(localized: "Volume up", comment: "Keyboard media bar: Volume up button"))
                holdButton(.brightnessDown, symbol: "sun.min", label: String(localized: "Brightness down", comment: "Keyboard media bar: Brightness down button"))
                holdButton(.brightnessUp, symbol: "sun.max", label: String(localized: "Brightness up", comment: "Keyboard media bar: Brightness up button"))
            }
        }
    }

    private func tapButton(_ key: MediaKey, symbol: String, label: String) -> some View {
        Button {
            viewModel.tapMediaKey(key)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(Color(.secondarySystemBackground)))
        .clipShape(Circle())
        .contentShape(Circle())
        .minimumTapTarget()
        .accessibleButton(label: LocalizedStringKey(label))
    }

    private func holdButton(_ key: MediaKey, symbol: String, label: String) -> some View {
        HoldMediaKeyButton(symbol: symbol, label: label, key: key, viewModel: viewModel)
    }
}

/// Volume/brightness buttons need a `@State` pressed-visual since they repeat while held rather
/// than firing once (docs/08 §3.1 "pressed `.tertiarySystemBackground`"), unlike `tapButton`'s
/// stateless single-tap circles above.
private struct HoldMediaKeyButton: View {
    let symbol: String
    let label: String
    let key: MediaKey
    let viewModel: KeyboardViewModel

    @State private var isPressing = false

    var body: some View {
        Image(systemName: symbol)
            .frame(width: 44, height: 44)
            .keyCapStyle(isPressing ? .pressed : .normal)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
                // No-op; press/release handled by `onPressingChanged` for host-style repeat.
            } onPressingChanged: { pressing in
                isPressing = pressing
                if pressing {
                    viewModel.beginMediaKeyRepeat(key)
                } else {
                    viewModel.endMediaKeyRepeat()
                }
            }
            .minimumTapTarget()
            .accessibleButton(label: LocalizedStringKey(label), hint: LocalizedStringKey("Hold to repeat"))
    }
}
