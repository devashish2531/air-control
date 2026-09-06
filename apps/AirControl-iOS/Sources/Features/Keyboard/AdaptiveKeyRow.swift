// Features/Keyboard/AdaptiveKeyRow.swift
// A key row that lays its buttons out in a single leading-aligned `HStack` when they fit the
// available width, and falls back to a wrapping grid (rather than clipping or overflowing off the
// trailing edge) when they don't — a narrower phone, or a larger Dynamic Type size expanding each
// button past its 44 pt minimum (spec §4.8.1.3: "larger text wraps rather than clips"). Shared by
// `ModifierBarView`'s row and `MediaKeyBarView`'s row; `ExtendedKeyBarView` (docs/08 §3.1) instead
// uses a single horizontally-scrolling strip since its full content never fits a phone width
// regardless of wrapping.

import SwiftUI

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
