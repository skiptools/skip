#if !SKIP
import class Foundation.DateFormatter
public typealias DateFormatter = Foundation.DateFormatter
public typealias PlatformDateFormatter = Foundation.DateFormatter
#else
public typealias DateFormatter = SkipDateFormatter
public typealias PlatformDateFormatter = java.text.DateFormat
#endif


// SKIP REPLACE: @JvmInline public value class SkipDateFormatter(val rawValue: PlatformDateFormatter) { companion object { } }
public struct SkipDateFormatter : RawRepresentable {
    public let rawValue: PlatformDateFormatter

    public init(rawValue: PlatformDateFormatter) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformDateFormatter) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension SkipDateFormatter {
}

#else

// SKIP XXX INSERT: public operator fun SkipDateFormatter.Companion.invoke(): SkipDateFormatter { return SkipDateFormatter(PlatformDateFormatter()) }

extension SkipDateFormatter {
}

#endif

