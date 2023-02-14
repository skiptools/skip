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

extension SkipBundle {
}

#else

// SKIP XXX INSERT: public operator fun SkipBundle.Companion.invoke(contentsOf: URL): SkipBundle { return SkipBundle(TODO) }

extension SkipBundle {
    public static var module: SkipBundle {
        get {
            // this could work better, but JDK 1.9 method is unable to be found…
            // SkipBundle(rawValue: java.lang.StackWalker().getInstance(java.lang.StackWalker.Option.RETAIN_CLASS_REFERENCE).getCallerClass())
            SkipBundle(rawValue: Class.forName(Thread.currentThread().getStackTrace()[2].getClassName()) as Class<Any>)
        }

        set {
            // unused, but needed by Skip
        }
    }

    // FIXME: this probably won't return what we expect, since the resources may live in another classloader
    public var resourceURL: SkipURL? {
        get {
            var url: java.net.URL? = rawValue.getResource(".")
            if (url != null) {
                SkipURL(url)
            } else {
                null
            }
        }

        set {
            // unused, but needed by Skip
        }
    }

    //url(forResource: "textasset", withExtension: "txt", subdirectory: nil, localization: nil)

    public func url(forResource: String, withExtension: String?, subdirectory: String?, localization: String?) -> URL? {
        var res = forResource
        if (withExtension != null) {
            res += "." + withExtension
        }
        if (subdirectory != null) {
            res = subdirectory + "/" + res
        }
        // TODO: localization?
        var url: java.net.URL? = rawValue.getResource(res)
        if (url != null) {
            return SkipURL(url)
        } else {
            return null
        }
    }
}

#endif

