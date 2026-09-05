// Services/KeyboardBridge/TextChunking.swift
// Grapheme-safe chunking for commit-mode sends (spec §4.4.2: "chunked on grapheme boundaries at
// 4 KB") — a pure, dependency-free helper so it is directly unit-testable.

public extension StringProtocol {
    /// Splits `self` into pieces of at most `maxBytes` UTF-8 bytes each, never splitting a
    /// `Character` (extended grapheme cluster) across a boundary. Returns `[]` for empty input,
    /// and a single element for input already under `maxBytes`.
    func chunkedByGraphemeClusters(maxBytes: Int) -> [String] {
        guard !isEmpty else { return [] }
        var chunks: [String] = []
        var current = ""
        var currentBytes = 0
        for character in self {
            let bytes = character.utf8.count
            if currentBytes + bytes > maxBytes, !current.isEmpty {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += bytes
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
