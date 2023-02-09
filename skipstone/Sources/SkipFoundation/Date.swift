#if !SKIP
import struct Foundation.Date
public typealias Date = Foundation.Date
public typealias PlatformDate = Foundation.NSDate
#else
public typealias Date = SkipDate
public typealias PlatformDate = java.util.Date
#endif

public typealias TimeInterval = Double

// SKIP REPLACE: @JvmInline public value class SkipDate(val rawValue: PlatformDate = PlatformDate()) { companion object { } }
public struct SkipDate : RawRepresentable {
    public let rawValue: PlatformDate

    public init(rawValue: PlatformDate) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformDate) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension Date {
    public static func create(timeIntervalSince1970: TimeInterval) -> Date {
        return Date(timeIntervalSince1970: timeIntervalSince1970)
    }

    public func getTime() -> TimeInterval {
        return self.timeIntervalSince1970
    }
}

#else

extension SkipDate {
    public static func create(timeIntervalSince1970: TimeInterval) -> SkipDate {
        return SkipDate(rawValue: PlatformDate((timeIntervalSince1970 * 1000.0).toLong()))
    }


    public func getTime() -> TimeInterval {
        return rawValue.getTime() / 1000.0
    }

    // FIXME: skip calculated prop yet supported
//    public var timeIntervalSince1970: TimeInterval {
//        rawValue.getTime() / 1000.0
//    }
}

#endif
