// Features/Keyboard/ExtendedKeyBarView.swift
// Extended key bar (spec §4.1.6): Esc, Tab, Return, ⌫/⌦, the arrow cluster, Home/End/PgUp/PgDn,
// and F1–F12 (fn toggle switches the F-row between F-keys and media glyphs, spec §4.4.4). The
// editing/nav clusters use `AdaptiveKeyRow` so they fit the screen width at every size class and
// Dynamic Type level instead of overflowing (wrapping to a second line rather than clipping); the
// F-row stays horizontally-scrolling since F1–F12 never all fit on a phone width (spec §4.8). Keys
// that auto-repeat while held (arrows, ⌫/⌦, PgUp/PgDn) report `isDown`/`isUp` on press/release
// (spec §4.4.3); everything else fires a single tap (`isDown` immediately followed by `isUp`).

import SwiftUI
import AirMouseProtocol

struct ExtendedKeyBarView: View {
    let viewModel: KeyboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AdaptiveKeyRow(spacing: 8) {
                ForEach(ExtendedKey.editingCluster) { keyButton($0) }
            }
            arrowsAndNav
            fRow
        }
    }

    /// The arrow cluster and Home/End/PgUp/PgDn cluster share one row when there's room, keeping
    /// each cluster's own 4-key grouping intact; on a narrower phone or larger Dynamic Type size
    /// where the two together don't fit, they stack as two neat 4-key rows instead of overflowing
    /// or wrapping into an uneven grid (spec §4.8.1.3).
    private var arrowsAndNav: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                clusterRow(ExtendedKey.arrowCluster)
                clusterRow(ExtendedKey.navCluster)
            }
            VStack(alignment: .leading, spacing: 8) {
                clusterRow(ExtendedKey.arrowCluster)
                clusterRow(ExtendedKey.navCluster)
            }
        }
    }

    private func clusterRow(_ keys: [ExtendedKey]) -> some View {
        HStack(spacing: 8) {
            ForEach(keys) { keyButton($0) }
        }
    }

    private func keyButton(_ key: ExtendedKey) -> some View {
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

/// A key row that lays its buttons out in a single leading-aligned `HStack` when they fit the
/// available width, and falls back to a wrapping grid (rather than clipping or overflowing off
/// the trailing edge) when they don't — a narrower phone, or a larger Dynamic Type size expanding
/// each button past its 44 pt minimum (spec §4.8.1.3: "larger text wraps rather than clips").
/// Shared by `ExtendedKeyBarView`'s editing/nav clusters and `ModifierBarView`'s row; the F-row and
/// shortcut row use a horizontally-scrolling `ScrollView` instead since their full content never
/// fits a phone width regardless of wrapping.
struct AdaptiveKeyRow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44, maximum: 64), spacing: spacing)],
                alignment: .leading,
                spacing: spacing
            ) {
                content
            }
        }
    }
}
