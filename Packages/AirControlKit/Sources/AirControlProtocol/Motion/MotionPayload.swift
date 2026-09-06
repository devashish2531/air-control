import Foundation

/// The 16-byte plaintext motion sample payload. spec §3.5.2:
/// ```
/// offset  size  field       description
/// 0       1     flags       bit0 scrollBegan · bit1 scrollEnded · bit2 motionEnd · bit3 predicted
///                            · bit4 probe · bit5 echo · bits6–7 reserved (0)
/// 1       1     source      0 touch · 1 gyro · 2 external pointer · 3 tcpFallback · 255 probe
/// 2       1     samples     number of raw sensor samples coalesced into this datagram, 1–255
///                            (0 for probe)
/// 3       1     reserved    must be 0
/// 4       4     timestamp   u32 LE, client monotonic clock in µs (wraps every 71.6 min)
/// 8       2     dx          i16 LE, pointer delta X in 1/8 point
/// 10      2     dy          i16 LE, pointer delta Y (positive = down)
/// 12      2     scrollX     i16 LE, scroll delta X in 1/8 point
/// 14      2     scrollY     i16 LE, scroll delta Y
/// ```
/// This is the plaintext carried inside the UDP datagram's AEAD ciphertext (§3.5.1) or, unencrypted,
/// inside a `kind = 0x02` TCP fallback batch frame body (§3.5.9). `AirControlCrypto` seals/opens it;
/// this module only packs and unpacks the 16 bytes.
///
/// `encode(into:)` / `init(bytes:)` use `withUnsafeBytes`/raw pointers directly — the one place
/// this module uses unsafe constructs — so a sender coalescing many samples per second allocates
/// nothing on the hot path (spec §6.2 (architecture): "the one allowed unsafe use, confined to a
/// 16-byte fixed buffer and fuzzed").
public struct MotionPayload: Sendable, Equatable {
    public var flags: MotionFlags
    public var source: MotionSource
    /// Raw sensor samples coalesced into this datagram, 1–255 (0 only for `source == .probe`).
    public var samples: UInt8
    /// Client monotonic clock, microseconds, wraps every 2^32 µs (~71.6 min); receivers must use
    /// modular arithmetic (spec §3.5.2).
    public var timestamp: UInt32
    /// Pointer delta X, 1/8-point fixed-point (see `MotionFixedPoint`).
    public var dx: Int16
    /// Pointer delta Y, positive = down.
    public var dy: Int16
    /// Scroll delta X, 1/8-point fixed-point (finger-travel units).
    public var scrollX: Int16
    /// Scroll delta Y.
    public var scrollY: Int16

    /// The wire size of this payload: always exactly 16 bytes.
    public static let byteCount = 16

    public init(
        flags: MotionFlags = [],
        source: MotionSource,
        samples: UInt8,
        timestamp: UInt32,
        dx: Int16 = 0,
        dy: Int16 = 0,
        scrollX: Int16 = 0,
        scrollY: Int16 = 0
    ) {
        self.flags = flags
        self.source = source
        self.samples = samples
        self.timestamp = timestamp
        self.dx = dx
        self.dy = dy
        self.scrollX = scrollX
        self.scrollY = scrollY
    }

    /// Convenience initializer taking deltas in points; converts through `MotionFixedPoint`.
    public init(
        flags: MotionFlags = [],
        source: MotionSource,
        samples: UInt8,
        timestamp: UInt32,
        dxPoints: Double,
        dyPoints: Double,
        scrollXPoints: Double,
        scrollYPoints: Double
    ) {
        self.init(
            flags: flags,
            source: source,
            samples: samples,
            timestamp: timestamp,
            dx: MotionFixedPoint.encode(dxPoints),
            dy: MotionFixedPoint.encode(dyPoints),
            scrollX: MotionFixedPoint.encode(scrollXPoints),
            scrollY: MotionFixedPoint.encode(scrollYPoints)
        )
    }

    public var dxPoints: Double { MotionFixedPoint.decode(dx) }
    public var dyPoints: Double { MotionFixedPoint.decode(dy) }
    public var scrollXPoints: Double { MotionFixedPoint.decode(scrollX) }
    public var scrollYPoints: Double { MotionFixedPoint.decode(scrollY) }

    /// Packs this payload into the first 16 bytes of `buffer` in the layout above.
    ///
    /// - Precondition: `buffer.count >= MotionPayload.byteCount`.
    public func encode(into buffer: UnsafeMutableRawBufferPointer) {
        precondition(buffer.count >= Self.byteCount, "MotionPayload.encode(into:) needs a 16-byte buffer")
        buffer.storeBytes(of: flags.rawValue, toByteOffset: 0, as: UInt8.self)
        buffer.storeBytes(of: source.rawValue, toByteOffset: 1, as: UInt8.self)
        buffer.storeBytes(of: samples, toByteOffset: 2, as: UInt8.self)
        buffer.storeBytes(of: UInt8(0), toByteOffset: 3, as: UInt8.self)
        buffer.storeBytes(of: timestamp.littleEndian, toByteOffset: 4, as: UInt32.self)
        buffer.storeBytes(of: dx.littleEndian, toByteOffset: 8, as: Int16.self)
        buffer.storeBytes(of: dy.littleEndian, toByteOffset: 10, as: Int16.self)
        buffer.storeBytes(of: scrollX.littleEndian, toByteOffset: 12, as: Int16.self)
        buffer.storeBytes(of: scrollY.littleEndian, toByteOffset: 14, as: Int16.self)
    }

    /// Encodes this payload into a freshly-allocated 16-byte `Data`. Prefer `encode(into:)` on a
    /// reused buffer for the hot send path; this convenience allocates.
    public func encoded() -> Data {
        var data = Data(count: Self.byteCount)
        data.withUnsafeMutableBytes { self.encode(into: $0) }
        return data
    }

    /// Unpacks a payload from the first 16 bytes of `bytes`.
    ///
    /// Returns `nil` if `bytes` is shorter than 16 bytes or `source` is not a recognized value
    /// (an unrecognized `source` most likely indicates a corrupt or adversarial datagram rather
    /// than a future spare value the caller should silently accept — spec §3.7 reserves spare
    /// `source` values for *new* sources, which would ship with a matching protocol update to this
    /// enum). Byte 3 (`reserved`) is read and discarded even if nonzero, per §3.7 ("ignored when
    /// received").
    public init?(bytes: UnsafeRawBufferPointer) {
        guard bytes.count >= Self.byteCount else { return nil }
        guard let source = MotionSource(rawValue: bytes.load(fromByteOffset: 1, as: UInt8.self)) else {
            return nil
        }
        self.flags = MotionFlags(rawValue: bytes.load(fromByteOffset: 0, as: UInt8.self))
        self.source = source
        self.samples = bytes.load(fromByteOffset: 2, as: UInt8.self)
        self.timestamp = bytes.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian
        self.dx = bytes.loadUnaligned(fromByteOffset: 8, as: Int16.self).littleEndian
        self.dy = bytes.loadUnaligned(fromByteOffset: 10, as: Int16.self).littleEndian
        self.scrollX = bytes.loadUnaligned(fromByteOffset: 12, as: Int16.self).littleEndian
        self.scrollY = bytes.loadUnaligned(fromByteOffset: 14, as: Int16.self).littleEndian
    }

    /// Convenience initializer from a `Data` value; must be exactly 16 bytes.
    public init?(data: Data) {
        guard data.count == Self.byteCount else { return nil }
        var decoded: MotionPayload?
        data.withUnsafeBytes { raw in decoded = MotionPayload(bytes: raw) }
        guard let decoded else { return nil }
        self = decoded
    }
}
