#if !SKIP
import struct Foundation.Locale
public typealias Locale = Foundation.Locale
public typealias PlatformLocale = Foundation.NSLocale
#else
public typealias Locale = SkipLocale
public typealias PlatformLocale = java.util.Locale
#endif

// two different ways of simulator constructor extensions

// SKIP INSERT: public operator fun SkipLocale.Companion.invoke(identifier: String): SkipLocale { return SkipLocale(PlatformLocale(identifier)) }
// SKIP XXX INSERT: public fun Locale(identifier: String): SkipLocale { return SkipLocale(PlatformLocale(identifier)) }

// SKIP REPLACE: @JvmInline public value class SkipLocale(val rawValue: PlatformLocale) { companion object { } }
public struct SkipLocale : RawRepresentable {
    public let rawValue: PlatformLocale

    public init(rawValue: PlatformLocale) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformLocale) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension SkipLocale {
}

#else

extension SkipLocale {
    public var identifier: String {
        //return rawValue.toLanguageTag()
        return rawValue.toString()
    }

    public var languageCode: String? {
        return rawValue.getLanguage()
    }
}

#endif
