// Features/Keyboard/ExtendedKeyBarView.swift
// Extended key bar (spec §4.1.6): Esc, Tab, Return, ⌫/⌦, the arrow cluster, Home/End/PgUp/PgDn,
// and F1–F12 (fn toggle switches the F-row between F-keys and media glyphs, spec §4.4.4). Laid
// out as horizontally-scrolling clusters so it fits a phone width while staying ≥ 44 pt per key
// (spec §4.8). Keys that auto-repeat while held (arrows, ⌫/⌦, PgUp/PgDn) report `isDown`/`isUp` on
// press/release (spec §4.4.3); everything else fires a single tap (`isDown` immediately followed
// by `isUp`).

import SwiftUI
import AirMouseProtocol

struct ExtendedKeyBarView: View {
    let viewModel: KeyboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            cluster(ExtendedKey.editingCluster)
            HStack(spacing: 16) {
                cluster(ExtendedKey.arrowCluster)
                cluster(ExtendedKey.navCluster)
            }
            fRow
        }
    }

    private func cluster(_ keys: [ExtendedKey]) -> some View {
        HStack(spacing: 8) {
            ForEach(keys) { key in
                ExtendedKeyButton(
                    symbolName: key.prefersTextGlyph ? nil : key.symbolName,
                    text: key.prefersTextGlyph ? key.label : nil,
                    accessibilityLabel: key.label,
                    autoRepeats: key.autoRepeatsOnHold,
                    onDown: { viewModel.pressExtendedKey(key, isDown: true) },
                    onUp: { viewModel.pressExtendedKey(key, isDown: false) },
                    onTap: { viewModel.tapExtendedKey(key) }
                )
            }
        }
    }

    private var fRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExtendedKey.functionRow) { key in
                    if viewModel.isFRowShowingMedia, let media = FRowMediaGlyph.mapping[key] {
                        ExtendedKeyButton(
                            symbolName: media.symbolName,
                            text: nil,
                            accessibilityLabel: media.label,
                            autoRepeats: false,
                            onDown: {},
                            onUp: {},
                            onTap: { viewModel.tapMediaKey(media.key) }
                        )
                    } else {
                        ExtendedKeyButton(
                            symbolName: nil,
                            text: key.label,
                            accessibilityLabel: key.label,
                            autoRepeats: false,
                            onDown: {},
                            onUp: {},
                            onTap: { viewModel.tapExtendedKey(key) }
                        )
                    }
                }
            }
        }
    }
}

private struct ExtendedKeyButton: View {
    let symbolName: String?
    let text: String?
    let accessibilityLabel: String
    let autoRepeats: Bool
    let onDown: () -> Void
    let onUp: () -> Void
    let onTap: () -> Void

    @State private var isPressing = false

    var body: some View {
        Group {
            if let symbolName {
                Image(systemName: symbolName)
            } else {
                Text(text ?? "")
            }
        }
        .font(.callout.weight(.medium))
        .frame(minWidth: 44, minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isPressing ? AnyShapeStyle(.tint.opacity(0.35)) : AnyShapeStyle(.quaternary.opacity(0.3)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity) {
            // `perform` fires on every recognised press; the real logic lives in `onPressingChanged`.
        } onPressingChanged: { pressing in
            guard pressing != isPressing else { return }
            isPressing = pressing
            if autoRepeats {
                if pressing { onDown() } else { onUp() }
            } else if pressing {
                onTap()
            }
        }
        .minimumTapTarget()
        .accessibleButton(label: LocalizedStringKey(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
    }
}
