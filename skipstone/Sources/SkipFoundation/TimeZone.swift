#if !SKIP
import struct Foundation.TimeZone
public typealias TimeZone = Foundation.TimeZone
public typealias PlatformTimeZone = Foundation.NSTimeZone
#else
public typealias TimeZone = SkipTimeZone
public typealias PlatformTimeZone = java.util.TimeZone
#endif


// SKIP REPLACE: @JvmInline public value class SkipTimeZone(val rawValue: PlatformTimeZone) { companion object { } }
public struct SkipTimeZone : RawRepresentable {
    public let rawValue: PlatformTimeZone

    public init(rawValue: PlatformTimeZone) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformTimeZone) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension SkipTimeZone {
}

#else

// SKIP XXX INSERT: public operator fun SkipTimeZone.Companion.invoke(contentsOf: URL): SkipTimeZone { return SkipTimeZone(TODO) }

extension SkipTimeZone {
}

#endif

