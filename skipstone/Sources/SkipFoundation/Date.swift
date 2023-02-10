#if !SKIP
import struct Foundation.Date
public typealias Date = Foundation.Date
public typealias PlatformDate = Foundation.NSDate
#else
public typealias Date = SkipDate
public typealias PlatformDate = java.util.Date
#endif


#if !SKIP
public let CFAbsoluteTimeGetCurrent = Foundation.CFAbsoluteTimeGetCurrent
#else

public typealias TimeInterval = Double
public typealias CFTimeInterval = TimeInterval

/// absolute time is the time interval since the reference date the reference date (epoch) is 00:00:00 1 January 2001.
public typealias CFAbsoluteTime = CFTimeInterval

public let kCFAbsoluteTimeIntervalSince1970: CFTimeInterval = 978307200.0


/// Absolute time is measured in seconds relative to the absolute reference date of Jan 1 2001 00:00:00 GMT. A positive value represents a date after the reference date, a negative value represents a date before it. For example, the absolute time -32940326 is equivalent to December 16th, 1999 at 17:54:34. Repeated calls to this function do not guarantee monotonically increasing results. The system time may decrease due to synchronization with external time references or due to an explicit user change of the clock.
public func CFAbsoluteTimeGetCurrent() -> CFAbsoluteTime {
    return (System.currentTimeMillis() / 1000.0) - kCFAbsoluteTimeIntervalSince1970
}

#endif

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

// SKIP INSERT: public operator fun SkipDate.Companion.invoke(timeIntervalSince1970: TimeInterval): SkipDate { return SkipDate.create(timeIntervalSince1970 = timeIntervalSince1970) }
// SKIP XXX INSERT: public fun Date(timeIntervalSince1970: TimeInterval): SkipDate { return SkipDate.create(timeIntervalSince1970 = timeIntervalSince1970) }

// [gradle] e: src/main/kotlin/skip/foundation/Date.kt:28:1 Conflicting overloads: public fun Date(timeIntervalSince1970: TimeInterval): SkipDate defined in skip.foundation in file Date.kt, public fun Date(timeIntervalSinceReferenceDate: TimeInterval): SkipDate defined in skip.foundation in file Date.kt
// SKIP INSERT: public fun Date(timeIntervalSinceReferenceDate: TimeInterval): SkipDate { return SkipDate.create(timeIntervalSince1970 = timeIntervalSinceReferenceDate + kCFAbsoluteTimeIntervalSince1970) }



// SKIP INSERT: public val SkipDate.Companion.distantPast: Date get() = Date.create(-62135769600.0)
// SKIP INSERT: public val SkipDate.Companion.distantFuture: Date get() = Date.create(64092211200.0)
// SKIP INSERT: public val SkipDate.timeIntervalSince1970: TimeInterval get() = rawValue.getTime() / 1000.0
// SKIP INSERT: public val SkipDate.timeIntervalSinceReferenceDate: TimeInterval get() = (rawValue.getTime() / 1000.0) - kCFAbsoluteTimeIntervalSince1970

extension SkipDate {
    // TODO: read-only val properties
    // public static var distantPast: Date { Date.create(-62135769600.0) }
    // public static var distantFuture: Date { Date.create(64092211200.0) }
    // public var timeIntervalSince1970: TimeInterval {
    //     rawValue.getTime() / 1000.0
    // }

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
    
}


#endif
