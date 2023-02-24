#if !SKIP
import class Foundation.Bundle
public typealias Bundle = Foundation.Bundle
public typealias PlatformBundle = Foundation.Bundle
#else
public typealias Bundle = SkipBundle
public typealias PlatformBundle = java.lang.Class<Any>
#endif


// SKIP REPLACE: @JvmInline public value class SkipBundle(val rawValue: PlatformBundle) { companion object { } }
public struct SkipBundle : RawRepresentable {
    public let rawValue: PlatformBundle

    public init(rawValue: PlatformBundle) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformBundle) {
        self.rawValue = rawValue
    }
}

#if !SKIP

extension PlatformBundle {
    /// The location of a bundle to use for looking up localized strings, such as the main bundle, or a bundle at a specific file URL.
    public var location: LocalizedStringResource.BundleDescription {
        .atURL(bundleURL)
    }
}

#else

// SKIP XXX INSERT: public operator fun SkipBundle.Companion.invoke(contentsOf: URL): SkipBundle { return SkipBundle(TODO) }

extension SkipBundle {
    /// Returns the description for this bundle, which in the case of Java, is the bundle itself
    public var location: SkipBundle? {
        return self
    }

    // FIXME: this probably won't return what we expect, since the resources may live in another classloader
    public var resourceURL: SkipURL? {
        get {
            var url: java.net.URL? = rawValue.getResource(".")
            if (url != null) {
                return SkipURL(url)
            } else {
                return null
            }
        }
    }

    public func url(forResource: String, withExtension: String?, subdirectory: String?, localization: String?) -> URL? {
        // similar behavior to: https://github.com/apple/swift-corelibs-foundation/blob/69ab3975ea636d1322ad19bbcea38ce78b65b26a/CoreFoundation/PlugIn.subproj/CFBundle_Resources.c#L1114
        var res = forResource
        if (withExtension != null) {
            res += "." + withExtension
        }
        if (localization != null) {
            //let lprojExtension = "lproj" // _CFBundleLprojExtension
            var lprojExtensionWithDot = ".lproj" // _CFBundleLprojExtensionWithDot
            res = localization + lprojExtensionWithDot + "/" + res
        }
        if (subdirectory != null) {
            res = subdirectory + "/" + res
        }
        var url: java.net.URL? = rawValue.getResource(res)
        if (url != null) {
            return SkipURL(url)
        } else {
            return null
        }
    }
}

#endif

