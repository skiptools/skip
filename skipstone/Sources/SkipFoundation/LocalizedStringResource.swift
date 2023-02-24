#if !SKIP
import struct Foundation.LocalizedStringResource
public typealias LocalizedStringResource = Foundation.LocalizedStringResource
#else
public typealias LocalizedStringResource = SkipLocalizedStringResource
#endif


public final class SkipLocalizedStringResource {
    public let key: String
    public let defaultValue: String? // TODO: String.LocalizationValue
    public let table: String?
    public var locale: SkipLocale?
    public var bundle: SkipBundle? // TODO: LocalizedStringResource.BundleDescription

    // SKIP REPLACE: constructor(key: String, defaultValue: String? = null, table: String? = null, locale: SkipLocale? = null, bundle: SkipBundle? = null) { this.key = key; this.defaultValue = defaultValue; this.table = table; this.locale = locale; this.bundle = bundle; }
    init(key: String, defaultValue: String, table: String?, locale: SkipLocale, bundle: SkipBundle) {
        self.key = key
        self.defaultValue = defaultValue
        self.table = table
        self.locale = locale
        self.bundle = bundle
    }


}

#if SKIP

// SKIP XXX INSERT: public operator fun SkipLocalizedStringResource.Companion.invoke(contentsOf: URL): SkipLocalizedStringResource { return SkipLocalizedStringResource(TODO) }

extension SkipLocalizedStringResource {
}

#endif

