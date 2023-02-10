#if !SKIP
import struct Foundation.UUID
public typealias UUID = Foundation.UUID
public typealias PlatformUUID = Foundation.NSUUID
#else
public typealias UUID = SkipUUID
public typealias PlatformUUID = java.util.UUID
#endif

// SKIP INSERT: public operator fun SkipUUID.Companion.invoke(uuidString: String): SkipUUID? { return SkipUUID.fromString(uuidString) }

// SKIP REPLACE: @JvmInline public value class SkipUUID(val rawValue: PlatformUUID = PlatformUUID.randomUUID()) { companion object { } }
public struct SkipUUID : RawRepresentable {
    public let rawValue: PlatformUUID

    public init(rawValue: PlatformUUID) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformUUID) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension UUID {
    /// Creates this UUID using the given most signifant bits and least significant bits.
    @inlinable public init(mostSigBits: Int64, leastSigBits: Int64) {
        var mostSigBits = mostSigBits
        var leastSigBits = leastSigBits
        self = withUnsafeBytes(of: &mostSigBits) { a in
            withUnsafeBytes(of: &leastSigBits) { b in
                UUID(uuid: (a[7], a[6], a[5], a[4], a[3], a[2], a[1], a[0], b[7], b[6], b[5], b[4], b[3], b[2], b[1], b[0]))
            }
        }
    }
}

#else

// SKIP INSERT: public fun UUID(mostSigBits: Long, leastSigBits: Long): SkipUUID { return SkipUUID(PlatformUUID(mostSigBits, leastSigBits)) }

extension SkipUUID {
    public static func fromString(uuidString: String) -> SkipUUID? {
        // Java throws an exception for bad UUID, but Foundation expects it to return nil
        return try? SkipUUID(rawValue: PlatformUUID.fromString(uuidString))
    }

    // TODO: constructor support (remove SKIP INSERT above)
//    public init(mostSigBits: Int64, leastSigBits: Int64) {
//        SkipUUID(mostSigBits, leastSigBits)
//    }

    public var uuidString: String {
        // java.util.UUID is lowercase, Foundation.UUID is uppercase
        return rawValue.toString().uppercase()
    }

    public var description: String {
        return uuidString
    }
}

#endif
