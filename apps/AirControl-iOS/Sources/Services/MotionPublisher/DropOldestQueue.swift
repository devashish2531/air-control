// Services/MotionPublisher/DropOldestQueue.swift
// Bounded FIFO with drop-oldest overflow policy, extracted as its own pure value type so
// `MotionPublisher`'s backpressure valve ("drop-oldest with a counter", this agent's assignment)
// is unit-testable on its own — independent of whether, under a synchronous `MotionDatagramSink`,
// the actor's normal drain-immediately flow ever actually lets the queue exceed `capacity` (see
// `MotionPublisher`'s file-level deviation note: under a real, fast, synchronous sink it never
// does; this is the defensive valve for whatever isn't true of that assumption in the future, or
// under a slow/misbehaving sink).
public struct DropOldestQueue<Element>: Sendable where Element: Sendable {
    public let capacity: Int
    public private(set) var elements: [Element] = []
    public private(set) var droppedCount: Int = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "DropOldestQueue capacity must be positive")
        self.capacity = capacity
        elements.reserveCapacity(capacity)
    }

    /// Appends `element`, dropping the oldest queued element (and incrementing `droppedCount`)
    /// first if the queue is already at `capacity`.
    public mutating func append(_ element: Element) {
        if elements.count >= capacity {
            elements.removeFirst()
            droppedCount += 1
        }
        elements.append(element)
    }

    /// Removes and returns every currently-queued element, oldest first.
    public mutating func drainAll() -> [Element] {
        defer { elements.removeAll(keepingCapacity: true) }
        return elements
    }

    public var isEmpty: Bool { elements.isEmpty }
    public var count: Int { elements.count }
}
