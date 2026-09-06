import Foundation

/// One user-configurable macro button. spec §5.5.1:
/// ```swift
/// public struct Macro: Codable, Identifiable, Hashable {
///   public var id: UUID; public var name: String /*1–24*/; public var icon: String /*SF Symbol*/
///   public var tint: Tint? /*12 named*/; public var action: MacroAction; public var page: Int /*0–5*/
///   public var order: Int; public var showOnMediaPage: Bool; public var requiresConfirmation: Bool
///   public var createdAt: Date; public var updatedAt: Date
/// }
/// ```
/// Validation (name length, page range, per-page/total counts, uniqueness) is `MacroValidator`'s
/// job, not this initializer's — the one rule enforced here unconditionally is spec §5.5.1's
/// "`requiresConfirmation` forced `true` for `appleScript`/`shellCommand`", because that is a
/// property of the action kind, not a limit `MacroValidator` checks across a list.
public struct Macro: Codable, Identifiable, Hashable, Sendable, Equatable {
    public var id: UUID
    /// 1–24 characters (`ProtocolConstants.macroNameMaxLength`).
    public var name: String
    /// SF Symbol name. Validated for known-ness only where SwiftUI/UIKit's symbol catalog is
    /// available (i.e. in the apps, not here — see `MacroValidator`'s doc comment).
    public var icon: String
    public var tint: MacroTint?
    public var action: MacroAction
    /// 0–5 (`ProtocolConstants.macroMaxPages` pages, zero-indexed).
    public var page: Int
    /// Position within `page`.
    public var order: Int
    public var showOnMediaPage: Bool
    public var requiresConfirmation: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        tint: MacroTint? = nil,
        action: MacroAction,
        page: Int,
        order: Int,
        showOnMediaPage: Bool = false,
        requiresConfirmation: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.tint = tint
        self.action = action
        self.page = page
        self.order = order
        self.showOnMediaPage = showOnMediaPage
        // spec §5.5.1: forced true for script kinds, regardless of what the caller passed.
        self.requiresConfirmation = action.isScript ? true : requiresConfirmation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// spec §5.5.1: "`isScript` computed property".
    public var isScript: Bool { action.isScript }
}
