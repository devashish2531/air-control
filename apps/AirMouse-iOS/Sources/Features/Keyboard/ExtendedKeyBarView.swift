// Features/Keyboard/ExtendedKeyBarView.swift
// docs/08 §3.1: "one horizontally scrolling ExtendedKeyBar with sections Esc/Tab/Return/⌫/⌦ ·
// arrows · Home/End/PgUp/PgDn · F1–F12 (section headers as tiny captions; snap by section)".
// Replaces the previous two-cluster/`AdaptiveKeyRow` layout — docs/08 §1 problem 3 called out that
// "modifier/extended/F-key rows use a lot of vertical space" — with a single scrolling strip so the
// whole bar occupies one row's height regardless of size class or Dynamic Type; `.scrollTargetLayout`
// + `.viewAligned` scroll behaviour makes it snap section-by-section (spec §4.1.6, §4.4.4 for the
// fn/media-glyph F-row toggle). Keys that auto-repeat while held (arrows, ⌫/⌦, PgUp/PgDn) report
// `isDown`/`isUp` on press/release (spec §4.4.3); everything else fires a single tap (`isDown`
// immediately followed by `isUp`).

import SwiftUI
import AirMouseProtocol

struct ExtendedKeyBarView: View {
    let viewModel: KeyboardViewModel

    private struct Section: Identifiable {
        let id: String
        let caption: String
        let keys: [ExtendedKey]
    }

    private var sections: [Section] {
        [
            Section(
                id: "editing",
                caption: String(localized: "Edit", comment: "Extended key bar section caption: Esc/Tab/Return/Delete"),
                keys: ExtendedKey.editingCluster
            ),
            Section(
                id: "arrows",
                caption: String(localized: "Arrows", comment: "Extended key bar section caption: arrow keys"),
                keys: ExtendedKey.arrowCluster
            ),
            Section(
                id: "nav",
                caption: String(localized: "Navigate", comment: "Extended key bar section caption: Home/End/Page Up/Page Down"),
                keys: ExtendedKey.navCluster
            ),
            Section(
                id: "function",
                caption: String(localized: "Function", comment: "Extended key bar section caption: F1–F12"),
                keys: ExtendedKey.functionRow
            ),
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 20) {
                ForEach(sections) { section in
                    sectionView(section)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .accessibilityElement(children: .contain)
    }

    private func sectionView(_ section: Section) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                ForEach(section.keys) { key in keyButton(in: section, key) }
            }
        }
    }

    @ViewBuilder
    private func keyButton(in section: Section, _ key: ExtendedKey) -> some View {
        if section.id == "function", viewModel.isFRowShowingMedia, let media = FRowMediaGlyph.mapping[key] {
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
        .keyCapStyle(isPressing ? .pressed : .normal)
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
