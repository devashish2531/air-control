// KeycodeMapper — reverse table (unmodified/shifted character → macOS virtual keycode) built from
// the current keyboard layout via `UCKeyTranslate`.
//
// spec §5.3.6: "if `char` is present and the current input source is not ANSI-compatible
// (`hostState.inputSource.ansi == false`), resolve `char` → keycode through a reverse table built
// with `UCKeyTranslate` over all keycodes × {no modifier, shift} at each input-source change
// (`kTISNotifySelectedKeyboardInputSourceChanged`); fall back to `code`."
// architecture §3.3: "Reverse table `Character → (keycode, needsShift)` built with `UCKeyTranslate`
// over all keycodes × {none, shift} on `kTISNotifySelectedKeyboardInputSourceChanged`; `ansi` flag
// for `hostState.inputSource`; used when `key.char` is present and layout is non-ANSI" — "table
// rebuilt on main-actor notification, then swapped in atomically as an immutable value".
import Foundation
import Carbon.HIToolbox
import os
import AirMouseProtocol

/// Resolves a `key` message's `code`/`char` pair to the macOS virtual keycode to inject, per the
/// rule in spec §5.3.6: on an ANSI-compatible layout the ANSI `code` from the wire is authoritative
/// (typing "A" on a Dvorak Mac should still hit the physical A key the client's bar drew); on a
/// non-ANSI layout (e.g. AZERTY, JIS) the requested `char` is looked up in a reverse table for the
/// *current* layout, built with `UCKeyTranslate`, so the character the user tapped actually appears.
///
/// Thread-safe: internal state is a single immutable `Snapshot` swapped under an unfair lock, so
/// `resolve(code:char:)` and `isANSILayout` may be called concurrently from any executor (in
/// particular the `EventInjector` actor's dedicated `inject` executor, per architecture §3.3) while
/// a rebuild — triggered from `kTISNotifySelectedKeyboardInputSourceChanged`, delivered on whatever
/// queue `DistributedNotificationCenter` chooses — replaces the whole snapshot at once.
public final class KeycodeMapper: Sendable {
    private struct Snapshot: Sendable {
        var reverseTable: [Character: UInt16] = [:]
        var isANSI: Bool = true
    }

    private let state = OSAllocatedUnfairLock(initialState: Snapshot())
    private let logger = Logger(subsystem: "com.airmouse.helper", category: "KeycodeMapper")

    public init() {
        rebuild()
        // spec §5.3.6 / architecture §3.3: rebuild the reverse table whenever the selected input
        // source changes. This notification is posted to the *distributed* notification center by
        // HIToolbox, not the process-local `NotificationCenter`.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.rebuild()
        }
    }

    /// Whether the current keyboard layout is ANSI-compatible (spec §5.3.4's `hostState.inputSource.ansi`).
    public var isANSILayout: Bool {
        state.withLock { $0.isANSI }
    }

    /// Resolves a `key{code, char?}` message to the macOS virtual keycode to inject (spec §5.3.6).
    /// On an ANSI-compatible layout — or when `char` is absent, or when the layout's reverse table
    /// has no entry for it — the wire's ANSI `code` is used as-is.
    public func resolve(code: UInt16, char: String?) -> UInt16? {
        guard let char, let character = char.first, char.count == 1 else { return code }
        return state.withLock { snapshot in
            guard !snapshot.isANSI else { return code }
            return snapshot.reverseTable[character] ?? code
        }
    }

    /// Rebuilds the reverse table and ANSI flag from the *current* keyboard layout input source,
    /// then swaps the new snapshot in atomically (architecture §3.3).
    private func rebuild() {
        let newSnapshot = Self.buildSnapshot(logger: logger)
        state.withLock { $0 = newSnapshot }
    }

    private static func buildSnapshot(logger: Logger) -> Snapshot {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else {
            logger.error("KeycodeMapper: no current keyboard layout input source; keeping US-ANSI fallback")
            return Snapshot()
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPointer).takeUnretainedValue()
        let keyboardType = UInt32(LMGetKbdType())
        // `KBGetLayoutType` returns `UInt32` and `kKeyboardANSI`/`kKeyboardISO`/`kKeyboardJIS` are
        // four-char codes (`kKeyboardANSI` == 'ANSI' == 0x414E5349), not small integers — comparing
        // through `Int16(...)` traps (`Int16` can't hold a value that size). Compare as `Int` instead.
        let isANSI = Int(KBGetLayoutType(Int16(LMGetKbdType()))) == kKeyboardANSI

        var reverseTable: [Character: UInt16] = [:]
        (layoutData as Data).withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let layoutPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return
            }
            // spec §5.3.6: "over all keycodes × {no modifier, shift}". kVK_* virtual keycodes span
            // 0x00...0x7F; unassigned codes simply fail to translate and are skipped below.
            for keyCode in UInt16(0)...UInt16(0x7F) {
                for modifierKeyState: UInt32 in [0, Self.shiftOnlyModifierKeyState] {
                    var deadKeyState: UInt32 = 0
                    var unicodeChars = [UniChar](repeating: 0, count: 4)
                    var actualLength = 0
                    let status = UCKeyTranslate(
                        layoutPointer,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        modifierKeyState,
                        keyboardType,
                        OptionBits(0),
                        &deadKeyState,
                        unicodeChars.count,
                        &actualLength,
                        &unicodeChars
                    )
                    guard status == noErr, actualLength > 0 else { continue }
                    let scalars = unicodeChars[0..<actualLength].compactMap { Unicode.Scalar($0) }
                    guard scalars.count == actualLength else { continue }
                    let string = String(String.UnicodeScalarView(scalars))
                    guard let character = string.first, string.count == 1 else { continue }
                    // First writer wins: the unmodified pass runs before the shifted pass per key
                    // code, so plain characters are preferred over shifted ones when both map to
                    // one physical key across the sweep (e.g. avoid a later key's shifted output
                    // clobbering an earlier key's unmodified one for the same character).
                    if reverseTable[character] == nil {
                        reverseTable[character] = keyCode
                    }
                }
            }
        }
        return Snapshot(reverseTable: reverseTable, isANSI: isANSI)
    }

    /// `UCKeyTranslate`'s modifier parameter is `(EventModifiers >> 8) & 0xFF`; Carbon's `shiftKey`
    /// (`0x0200`) shifted down 8 bits is `0x02`.
    private static let shiftOnlyModifierKeyState: UInt32 = 0x02
}
