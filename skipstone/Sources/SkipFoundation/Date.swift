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

// SKIP INSERT: public val SkipDate.Companion.distantPast: Date get() = Date.create(-62135769600.0)
// SKIP INSERT: public val SkipDate.Companion.distantFuture: Date get() = Date.create(64092211200.0)

extension SkipDate {
    #warning("TODO: translate static getters")
    // public static var distantPast: Date { Date.create(-62135769600.0) }
    // public static var distantFuture: Date { Date.create(64092211200.0) }


    public static func create(timeIntervalSince1970: TimeInterval) -> SkipDate {
        return SkipDate(rawValue: PlatformDate((timeIntervalSince1970 * 1000.0).toLong()))
    }


    public func getTime() -> TimeInterval {
        return rawValue.getTime() / 1000.0
    }

    public func ISO8601Format() -> String {
        // local time zone specific
        // return java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.getDefault()).format(rawValue)
        var dateFormat = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.getDefault())
        dateFormat.timeZone = java.util.TimeZone.getTimeZone("GMT")
        return dateFormat.format(rawValue)

    }

    #warning("TODO: translate calclated prop")
//    public var timeIntervalSince1970: TimeInterval {
//        rawValue.getTime() / 1000.0
//    }
}

#endif
