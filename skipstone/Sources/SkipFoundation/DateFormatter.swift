#if !SKIP
import class Foundation.DateFormatter
public typealias DateFormatter = Foundation.DateFormatter
public typealias PlatformDateFormatter = Foundation.DateFormatter
#else
public typealias DateFormatter = SkipDateFormatter
public typealias PlatformDateFormatter = java.text.SimpleDateFormat
#endif

// SKIP REPLACE: @JvmInline public value class SkipDateFormatter(val rawValue: PlatformDateFormatter = PlatformDateFormatter()) { companion object { } }
public struct SkipDateFormatter : RawRepresentable {
    public let rawValue: PlatformDateFormatter

    public init(rawValue: PlatformDateFormatter) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformDateFormatter) {
        self.rawValue = rawValue
    }
}

#if SKIP

extension SkipDateFormatter {
    public var dateFormat: String {
        get {
            return rawValue.toPattern()
        }

        set {
            rawValue.applyPattern(newValue)
        }
    }

    public static func dateFormat(fromTemplate: String, options: Int, locale: Locale) -> SkipDateFormatter {
        // TODO: check options?
        return SkipDateFormatter(rawValue: PlatformDateFormatter(fromTemplate, locale.rawValue))
    }
}
#else

#endif
