// Features/Touchpad/TouchpadSidePanelRail.swift
// Collapsed form of `TouchpadSidePanelSlot` (spec §4.1.10: "the side panel collapses to a 44 pt
// rail below 700 pt width"). A tap expands back to the full slot; the expand/collapse state is
// owned by `TouchpadScreen`.

import SwiftUI

public struct TouchpadSidePanelRail: View {
    let onExpand: () -> Void

    public init(onExpand: @escaping () -> Void) {
        self.onExpand = onExpand
    }

    public var body: some View {
        Button(action: onExpand) {
            VStack {
                Spacer()
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                Spacer()
            }
            .frame(minWidth: 44, maxWidth: 44, maxHeight: .infinity)
            .background(.thinMaterial)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SwiftUI.Text("Expand side panel", comment: "Accessibility label for the collapsed iPad side panel rail"))
    }
}

#Preview {
    TouchpadSidePanelRail(onExpand: {})
}
