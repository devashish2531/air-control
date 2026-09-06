// Temporary no-op `EventInjecting` so Pause Input has something to toggle before the injection agent's
// `EventInjector` actor (arch §3.3) exists. Posts nothing; owns no CGEventSource.
public actor PlaceholderEventInjector: EventInjecting {
    private var paused = false

    public init() {}

    public var isPaused: Bool {
        get async { paused }
    }

    public func pause() async { paused = true }
    public func resume() async { paused = false }
}
