// Features/Touchpad/TouchpadGridBackground.swift
// Subtle dot-grid texture behind the touchpad surface (spec §4.1.4: "subtle dot-grid texture").
// docs/08 §2.4: 24 pt spacing, 1.5 pt dots, colour `.primary.opacity(0.06)` light / `0.10` dark —
// `Color.primary` alone doesn't hit that exact weight in both themes (it's near-black in light,
// near-white in dark), so the opacity is picked per `colorScheme` rather than left constant.
// Pure decoration — drawn under the UIKit `TouchpadView`, never intercepts touches.

import SwiftUI

public struct TouchpadGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24 // docs/08 §2.4
            let dotSize: CGFloat = 1.5 // docs/08 §2.4
            let dotColor = Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06) // docs/08 §2.4
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    y += spacing
                }
                x += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    TouchpadGridBackground()
        .background(Color(.systemBackground))
}
