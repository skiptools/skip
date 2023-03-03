#if !SKIP
/// Needed unti Skip supports creating typealias inside extensions
public typealias StringEncoding = String.Encoding
#else

extension String {
    public func data(using: StringEncoding, allowLossyConversion: Bool) -> Data? {
        return try? Data(rawValue: toByteArray(using.encoding))
    }
}


// SKIP REPLACE: @JvmInline public value class StringEncoding(val encoding: java.nio.charset.Charset) { companion object { public val utf8 = StringEncoding(encoding = Charsets.UTF_8) } }
public struct StringEncoding : RawRepresentable {
    public let encoding: java.nio.charset.Charset

    public init(encoding: java.nio.charset.Charset) {
        self.encoding = encoding
    }

    public init(_ encoding: java.nio.charset.Charset) {
        self.encoding = encoding
    }
}

//public extension StringEncoding {
//    public static var utf8 = StringEncoding(encoding: Charsets.UTF_8)
//}


public class PropertyListSerialization {
    private static var plistRegex = getPlistRegex().toRegex()

    private static func getPlistRegex() -> String {
        // SKIP REPLACE: return """(?<!\\)"(.*?)(?<!\\)"\s*=\s*"(.*?)(?<!\\)";"""
        return null
    }

    /// Creates and returns a property list from the specified data.
    ///
    /// NOTE: this currenly only supports the strings format ("key" = "value"). XML and binary plists are TODO.
    public static func propertyList(from: Data, format: String?) -> Map<String, String>? {
        // SKIP REPLACE: return plistRegex.findAll(String(from.rawValue)).map { it.groupValues[1].replace("\\\\\\\"", "\"") to it.groupValues[2].replace("\\\\\\\"", "\"") }.toMap()
        return nil
    }
}
#endif
