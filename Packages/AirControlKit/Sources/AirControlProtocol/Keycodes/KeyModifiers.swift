// KeyModifiers — the wire's modifier flag set.
//
// spec §11.1: `click`/`key` carry `modifiers` [enum(cmd|opt|ctrl|shift|fn)]; the standalone
// `modifiers` message carries `flags` [enum(cmd|opt|ctrl|shift|fn|capsLock)] as an absolute set
// (§4.4.4: "Caps Lock is a locked ⇧ flag (`capsLock` in `modifiers`), not the hardware LED state").
// On the wire this is a JSON array of those enum strings, never a bitmask — `KeyModifiers` is an
// `OptionSet` for ergonomic use on the Swift side (union, `.contains`, diffing in §5.3.6's modifier
// diff), with a custom `Codable` conformance that encodes/decodes exactly that array-of-strings
// shape. The bit layout of `rawValue` is an internal implementation detail with no wire meaning.
public struct KeyModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0) // wire: "cmd"
    public static let option = KeyModifiers(rawValue: 1 << 1) // wire: "opt"
    public static let control = KeyModifiers(rawValue: 1 << 2) // wire: "ctrl"
    public static let shift = KeyModifiers(rawValue: 1 << 3) // wire: "shift"
    public static let function = KeyModifiers(rawValue: 1 << 4) // wire: "fn"
    public static let capsLock = KeyModifiers(rawValue: 1 << 5) // wire: "capsLock" (modifiers msg only)

    /// The macOS virtual keycode that reports this modifier via `flagsChanged` (spec §5.3.6: "⌘
    /// 0x37, ⌥ 0x3A, ⌃ 0x3B, ⇧ 0x38, fn 0x3F, caps as ⇧ flag"). `capsLock` posts the same keycode
    /// as `shift` per the spec, since it is carried as a locked ⇧ flag rather than a hardware key.
    public var virtualKeycode: UInt16? {
        switch self {
        case .command: VirtualKey.kVK_Command
        case .option: VirtualKey.kVK_Option
        case .control: VirtualKey.kVK_Control
        case .shift, .capsLock: VirtualKey.kVK_Shift
        case .function: VirtualKey.kVK_Function
        default: nil // not a single-bit value
        }
    }

    private static let wireOrder: [(KeyModifiers, String)] = [
        (.command, "cmd"),
        (.option, "opt"),
        (.control, "ctrl"),
        (.shift, "shift"),
        (.function, "fn"),
        (.capsLock, "capsLock"),
    ]
}

extension KeyModifiers: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: KeyModifiers = []
        while !container.isAtEnd {
            let name = try container.decode(String.self)
            guard let (flag, _) = Self.wireOrder.first(where: { $0.1 == name }) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown modifier value: \(name)"
                )
            }
            result.insert(flag)
        }
        self = result
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for (flag, name) in Self.wireOrder where contains(flag) {
            try container.encode(name)
        }
    }
}
