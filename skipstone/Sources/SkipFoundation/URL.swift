#if !SKIP
import struct Foundation.URL
public typealias URL = Foundation.URL
public typealias PlatformURL = Foundation.NSURL
#else
public typealias URL = SkipURL
public typealias PlatformURL = java.net.URL
#endif

// SKIP REPLACE: @JvmInline public value class SkipURL(val rawValue: PlatformURL) { companion object { } }
public struct SkipURL : RawRepresentable {
    public let rawValue: PlatformURL

    public init(rawValue: PlatformURL) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: PlatformURL) {
        self.rawValue = rawValue
    }
}

extension SkipURL {
    public var host: String? {
        return rawValue.host
    }
}

#if !SKIP


#else // stuff that doesn't compile in Swift (yet?)

extension SkipURL {
    public var path: String {
        return rawValue.path
    }

    public static func `init`(string: String) -> SkipURL {
        return SkipURL(PlatformURL(string))
    }

    public static func `init`(string: String, relativeTo: SkipURL) -> SkipURL {
        return SkipURL(PlatformURL(relativeTo.rawValue, string))
    }

    public static func `init`(fileURLWithPath path: String, isDirectory: Bool) -> SkipURL {
        return SkipURL(PlatformURL("file://" + path)) // TODO: isDirectory handling?
    }

    public var absoluteString: String {
        return rawValue.toExternalForm()
    }

    public var lastPathComponent: String? {
        return rawValue.path.split("/").last()
    }

    public var pathExtension: String? {
        return lastPathComponent?.split(".")?.last()
    }

    public var isFileURL: Bool {
        return rawValue.`protocol` == "file"
    }
}
#endif


// MARK: Unavailability Warnings

#if !SKIP
extension URL {
    @available(*, deprecated, message: "no kotlin equivalent")
    public var relativePath: String? {
        fatalError("no kotlin equivalent")
    }
}
#endif
