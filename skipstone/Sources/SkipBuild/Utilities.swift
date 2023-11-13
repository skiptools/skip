import Foundation

extension Collection {
    /// Returns the substring of the given string, safely handling index bounds
    public func slice(_ i1: Int, _ i2: Int? = nil) -> SubSequence {
        guard let start = index(startIndex, offsetBy: i1, limitedBy: endIndex) else {
            return self[startIndex..<startIndex]
        }

        let end = i2.flatMap { index(startIndex, offsetBy: $0, limitedBy: endIndex) } ?? endIndex

        return self[start..<end]
    }
}

extension BinaryInteger {
    /// Returns a string describing the number of bytes
    var byteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

/// Terminal output information, such as how to output messages in various ANSI colors.
public struct Term {
    public static let plain = Term(colors: false)
    public static let ansi = Term(colors: true)

    /// Whether to use color or plain output
    public let colors: Bool

    fileprivate func color(_ string: any StringProtocol, code: Color) -> String {
        if colors == false {
            return string.description // return the plain string
        } else {
            return code.rawValue + string + Color.reset.rawValue
        }
    }

    /// Returns the string with and ANSI `black` code when colors are enabled, or the raw string when they are disabled
    public func black(_ string: any StringProtocol) -> String { color(string, code: .black) }
    /// Returns the string with and ANSI `red` code when colors are enabled, or the raw string when they are disabled
    public func red(_ string: any StringProtocol) -> String { color(string, code: .red) }
    /// Returns the string with and ANSI `green` code when colors are enabled, or the raw string when they are disabled
    public func green(_ string: any StringProtocol) -> String { color(string, code: .green) }
    /// Returns the string with and ANSI `yellow` code when colors are enabled, or the raw string when they are disabled
    public func yellow(_ string: any StringProtocol) -> String { color(string, code: .yellow) }
    /// Returns the string with and ANSI `blue` code when colors are enabled, or the raw string when they are disabled
    public func blue(_ string: any StringProtocol) -> String { color(string, code: .blue) }
    /// Returns the string with and ANSI `magenta` code when colors are enabled, or the raw string when they are disabled
    public func magenta(_ string: any StringProtocol) -> String { color(string, code: .magenta) }
    /// Returns the string with and ANSI `cyan` code when colors are enabled, or the raw string when they are disabled
    public func cyan(_ string: any StringProtocol) -> String { color(string, code: .cyan) }
    /// Returns the string with and ANSI `gray` code when colors are enabled, or the raw string when they are disabled
    public func gray(_ string: any StringProtocol) -> String { color(string, code: .gray) }
    /// Returns the string with and ANSI `white` code when colors are enabled, or the raw string when they are disabled
    public func white(_ string: any StringProtocol) -> String { color(string, code: .white) }

    // ANSI escape sequences for text colors
    fileprivate enum Color : String, CaseIterable {
        static let esc = "\u{001B}"

        case reset = "\u{001B}[0m"
        case black = "\u{001B}[30m"
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        case gray = "\u{001B}[30;1m"
    }

    public static func stripANSIAttributes(from text: String) -> String {
        guard !text.isEmpty else { return text }

        // ANSI attribute is always started with ESC and ended by `m`
        var txt = text.split(separator: Term.Color.esc)
        for (i, sub) in txt.enumerated() {
            if let end = sub.firstIndex(of: "m") {
                txt[i] = sub[sub.index(after: end)...]
            }
        }
        return txt.joined()
    }
}

#if canImport(ImageIO)
import ImageIO
import struct UniformTypeIdentifiers.UTType
#endif

/// Creates a rectangular PNG filled with the specified
func createSolidColorPNG(width: Int, height: Int, hexString: String?, alpha: Double = 1.0) -> Data? {
    func hexStringToRGB(hexString: String) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        var formattedHex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        formattedHex = formattedHex.replacingOccurrences(of: "#", with: "")

        var hexValue: UInt64 = 0

        guard Scanner(string: formattedHex).scanHexInt64(&hexValue) else {
            return nil
        }

        let red = UInt8((hexValue & 0xFF0000) >> 16)
        let green = UInt8((hexValue & 0x00FF00) >> 8)
        let blue = UInt8(hexValue & 0x0000FF)

        return (red, green, blue)
    }

    guard let hexString = hexString, let (r, g, b) = hexStringToRGB(hexString: hexString) else {
        return nil
    }

#if !canImport(ImageIO)
    return nil
#else
    let bytesPerPixel = 4
    let bitsPerComponent = 8
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerPixel * width, space: colorSpace, bitmapInfo: bitmapInfo) else {
        return nil
    }

    context.setFillColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: alpha)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    guard let cgImage = context.makeImage() else {
        return nil
    }

    let pngData = NSMutableData()
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0] // Set compression quality to 1.0 (highest)
    guard let destination = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, options as CFDictionary) else {
        return nil
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)

    return pngData as Data
#endif
}


extension FileManager {
#if os(iOS)
    var homeDirectoryForCurrentUser: URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }
#endif

    /// Sets the modification time of all the files and folders under the given directory (inclusive) to the epoch, which defaults to January 1970.
    func zeroFileTimes(under directory: URL, epoch: Date = Date(timeIntervalSince1970: 0.0)) throws {
        if let pathEnumerator = self.enumerator(at: directory, includingPropertiesForKeys: nil, options: []) {
            for path in pathEnumerator {
                if let url = path as? URL {
                    try self.setAttributes([FileAttributeKey.modificationDate: epoch], ofItemAtPath: url.path)
                }
            }
        }

        // the parent directory itself is not included in the enumerator
        try self.setAttributes([FileAttributeKey.modificationDate: epoch], ofItemAtPath: directory.path)
    }

    /// Creates a directory at the given URL, permitting the case where the directory already exists
    func mkdir(_ fileURL: URL) throws -> URL {
        do {
            try createDirectory(at: fileURL, withIntermediateDirectories: false)
        } catch let error as NSError {
            // is we failed because the directory already exists, and the directory does exist, then pass
            if !(error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError)
                || (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                throw error
            }
        }
        return fileURL
    }
}



extension URL {
    /// Returns a human-readable description of the size of the underlying file for this URL, throwing an error if the file doesn't exist or cannot be accessed
    var fileSizeString: String {
        get throws {
            try ByteCountFormatter.string(fromByteCount: Int64(resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), countStyle: .file)
        }
    }

    /// Create the child directory of the given parent
    func append(path: String, create directory: Bool = false) throws -> URL {
        let path = appendingPathComponent(path, isDirectory: directory)
        return directory ? try FileManager.default.mkdir(path) : path
    }

    /// Returns true if the given file URL exists.
    /// - Parameter isDirectory: if specified, this will fail is the URL's directory status does not match the argument
    /// - Returns: true if the file exists (and, optionally, matches the isDirectory flag)
    func fileExists(isDirectory: Bool? = nil) -> Bool {
        guard let res = self.fileResources else {
            return false
        }
        if let isDirectory = isDirectory {
            return isDirectory == res.isDirectory
        }
        return true
    }

    /// Creates this file URL directory and returns the URL itself
    @discardableResult func createDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }

    /// Creates this file's parent URL directory and returns the URL itself
    @discardableResult func createParentDirectory() throws -> URL {
        try deletingLastPathComponent().createDirectory()
        return self
    }

    var fileResources: URLResourceValues? {
        try? self.resourceValues(forKeys: [.isReadableKey, .isWritableKey, .isExecutableKey, .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
    }

    var isReadableFile: Bool? {
        try? self.resourceValues(forKeys: [.isReadableKey]).isReadable
    }

    var isWritableFile: Bool? {
        try? self.resourceValues(forKeys: [.isWritableKey]).isWritable
    }

    var isExecutableFile: Bool? {
        try? self.resourceValues(forKeys: [.isExecutableKey]).isExecutable
    }

    var isDirectoryFile: Bool? {
        try? self.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
    }

    var isRegularFile: Bool? {
        try? self.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile
    }

    var isSymbolicLink: Bool? {
        try? self.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
    }

    var fileSize: Int? {
        try? self.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    func resolve(_ relative: String, check: (URL, Bool) throws -> ()) rethrows -> URL {
        let isDirectory = relative.hasSuffix("/")
        let url = self.appendingPathComponent(relative, isDirectory: isDirectory)
        try check(url, isDirectory)
        return url
    }
}


