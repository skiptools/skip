#if !SKIP
import struct Foundation.Calendar
public typealias Calendar = Foundation.Calendar
public typealias PlatformCalendar = Foundation.NSCalendar
#else
public typealias Calendar = SkipCalendar
public typealias PlatformCalendar = java.util.Calendar
#endif

// SKIP REPLACE: @JvmInline public value class SkipCalendar(val rawValue: PlatformCalendar) { companion object { } }
public struct SkipCalendar : RawRepresentable {
    public let rawValue: PlatformCalendar

    public init(rawValue: PlatformCalendar) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformCalendar) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension SkipCalendar {
}

#else

// SKIP XXX INSERT: public operator fun SkipCalendar.Companion.invoke(contentsOf: URL): SkipCalendar { return SkipCalendar(TODO) }

extension SkipCalendar {
}

#endif

