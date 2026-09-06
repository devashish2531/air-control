/// spec §4.2.6: "Apple Pencil (`type == .pencil`) is treated as a one-finger touch with no pressure
/// semantics; hover is ignored." Kept distinct from `.finger` only in case a future rule needs it.
public enum TouchKind: Sendable, Equatable {
    case finger
    case pencil
}
