/// spec §5.3.3: a click can be a `tap` (down+up bundled, host schedules the up 15 ms later), or an
/// explicit `down`/`up` pair for a drag press-and-hold.
public enum ClickKind: Sendable, Equatable {
    case tap
    case down
    case up
}
