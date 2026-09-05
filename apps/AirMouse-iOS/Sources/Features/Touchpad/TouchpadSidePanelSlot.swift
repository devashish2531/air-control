// Features/Touchpad/TouchpadSidePanelSlot.swift
// Placeholder for the iPad regular-width side panel (spec §4.1.10: "Side panel with tabs Keys /
// Macros / Presenter; the side panel collapses to a 44 pt rail below 700 pt width"). This agent
// owns only the touchpad surface and motion pipeline; the integration agent fills this slot with
// the real Keys/Macros/Presenter tab content once those features exist in this layout.

import SwiftUI

public struct TouchpadSidePanelSlot: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sidebar.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            SwiftUI.Text("Keys / Macros / Presenter", comment: "iPad Touchpad side panel placeholder body")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(.thinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SwiftUI.Text("Side panel placeholder", comment: "Accessibility label for the iPad side panel slot"))
    }
}

#Preview {
    TouchpadSidePanelSlot()
}
