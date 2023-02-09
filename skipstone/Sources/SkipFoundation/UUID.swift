#if !SKIP
import struct Foundation.UUID
public typealias UUID = Foundation.UUID
public typealias PlatformUUID = Foundation.NSUUID
#else
public typealias UUID = SkipUUID
public typealias PlatformUUID = java.util.UUID
#endif


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
    // FIXME: optional support
    public static func fromUUIDString(uuid: String) -> UUID! {
        return PlatformUUID(uuidString: uuid) as? UUID
    }
}

#else

extension SkipUUID {
    public var uuidString: String {
        // java.util.UUID is lowercase, Foundation.UUID is uppercase
        return rawValue.toString().uppercase()
    }

    public static func fromUUIDString(uuid: String) -> SkipUUID {
        return SkipUUID(rawValue: PlatformUUID.fromString(uuid))
    }
}

#endif
