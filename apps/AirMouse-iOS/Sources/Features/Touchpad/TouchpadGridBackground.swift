// Features/Touchpad/TouchpadGridBackground.swift
// Subtle dot-grid texture behind the touchpad surface (spec §4.1.4: "subtle dot-grid texture").
// Pure decoration — drawn under the UIKit `TouchpadView`, never intercepts touches.

import SwiftUI

public struct TouchpadGridBackground: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            let dotSize: CGFloat = 1.4
            var x: CGFloat = spacing / 2
            while x < size.width {
                var y: CGFloat = spacing / 2
                while y < size.height {
                    let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.18)))
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
