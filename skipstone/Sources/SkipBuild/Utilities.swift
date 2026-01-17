// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Retries the given block with an exponential backoff in between attempts.
///
/// The default `backoff` block will retry the `block` 5 times with an exponential backoff (1, 4, 9, 16, and 25 seconds).
///
/// - Parameters:
///   - backoff: a block taking an error failure and the retry index, and returns either a `TimeInterval` for the next backoff or `nil` if the error should be thrown
///   - block: the block to retry
/// - Throws: the final error that is throws after the `backoff` block returns `nil`
/// - Returns: the result of a successfull executed block
func retry<T>(backoff: (Error, Int) -> TimeInterval? = { _, retryIndex in retryIndex >= 5 ? nil : TimeInterval(retryIndex * retryIndex) }, block: () async throws -> T) async throws -> T {
    var retryCount = 0
    while true {
        retryCount += 1
        do {
            return try await block()
        } catch {
            guard let backoff = backoff(error, retryCount) else {
                throw error
            }
            // exponential backoff before retrying
            try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
    }
}

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

extension NSRegularExpression {
    /// Returns the array of matches for a string against the regular expression.
    func extract(from string: String, options: NSRegularExpression.MatchingOptions = []) -> [String]? {
        guard let match = firstMatch(in: string, options: options, range: NSRange(string.startIndex..., in: string)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map {
            (string as NSString).substring(with: match.range(at: $0))
        }
    }
}

extension String {
    @inlinable func hexEncodedString() -> String {
        (data(using: .utf8) ?? Data()).hexEncodedString()
    }
}

extension Data {
    /// Create a data instance from a hex string
    @inlinable init?(hexString: String) {
        var hex = hexString
        // If the hex string has an odd number of characters, pad it with a leading zero
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        // Create an array of bytes from the hex string
        var bytes = [UInt8]()

        for i in stride(from: 0, to: hex.count, by: 2) {
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            let hexByte = hex[start..<end]
            if let byte = UInt8(hexByte, radix: 16) {
                bytes.append(byte)
            } else {
                return nil
            }
        }

        self = Data(bytes)
    }
}

extension Sequence where Element == UInt8 {
    /// Encodes a `Data` or `Array<UInt8>` as a hex string
    @inlinable func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

/// A sequence that both `Data` and `String.UTF8View` conform to.
extension Data {
    func SHA256HashData() -> [UInt8] {
        SHA256(Array(self)).calculateHash()
    }

    func SHA256Hash() -> String {
        SHA256HashData().compactMap { String(format: "%02x", $0) }.joined()
    }
}

extension URL {
    /// Calculates the hash from a file URL and returns the SHA256 hash.
    func SHA256Hash() throws -> String {
        try Data(contentsOf: self).SHA256Hash()
    }
}

/// Internal SHA256 implementation
private final class SHA256 {
    static let h: Array<UInt64> = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    static let k: Array<UInt64> = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]

    let message: Array<UInt8>

    init(_ message: Array<UInt8>) {
        self.message = message
    }

    func calculateHash() -> Array<UInt8> {
        func rotateRight(_ value: UInt32, by: UInt32) -> UInt32 {
            (value >> by) | (value << (32 - by))
        }

        func arrayOfBytes(value: Int, length: Int) -> Array<UInt8> {
            withUnsafeBytes(of: value.bigEndian) { Array($0.prefix(length)) }
        }

        var buffer = bitPadding(to: self.message, blockSize: 64, allowance: 64 / 8)

        // hash values
        var hh = Array<UInt32>()
        Self.h.forEach {(h) -> () in
            hh.append(UInt32(h))
        }

        // append message length, in a 64-bit big-endian integer. So now the message length is a multiple of 512 bits.
        buffer += arrayOfBytes(value: message.count * 8, length: 64 / 8)

        // Process the message in successive 512-bit chunks:
        let chunkSizeBytes = 512 / 8 // 64
        for chunk in BytesSequence(chunkSize: chunkSizeBytes, data: buffer) {
            // break chunk into sixteen 32-bit words M[j], 0 ≤ j ≤ 15, big-endian
            // Extend the sixteen 32-bit words into sixty-four 32-bit words:
            var M = Array<UInt32>(repeating: 0, count: Self.k.count)
            for x in 0..<M.count {
                switch x {
                case 0...15:
                    let start = chunk.startIndex + (x * MemoryLayout<UInt32>.size)
                    let end = start + MemoryLayout<UInt32>.size
                    let le = chunk[start..<end].toUInt32Array()[0]
                    M[x] = le.bigEndian
                    break
                default:
                    let s0 = rotateRight(M[x-15], by: 7) ^ rotateRight(M[x-15], by: 18) ^ (M[x-15] >> 3)
                    let s1 = rotateRight(M[x-2], by: 17) ^ rotateRight(M[x-2], by: 19) ^ (M[x-2] >> 10)
                    M[x] = M[x-16] &+ s0 &+ M[x-7] &+ s1
                    break
                }
            }

            var A = hh[0]
            var B = hh[1]
            var C = hh[2]
            var D = hh[3]
            var E = hh[4]
            var F = hh[5]
            var G = hh[6]
            var H = hh[7]

            // main loop
            for j in 0..<Self.k.count {
                let s0 = rotateRight(A, by: 2) ^ rotateRight(A, by: 13) ^ rotateRight(A, by: 22)
                let maj = (A & B) ^ (A & C) ^ (B & C)
                let t2 = s0 &+ maj
                let s1 = rotateRight(E, by: 6) ^ rotateRight(E, by: 11) ^ rotateRight(E, by: 25)
                let ch = (E & F) ^ ((~E) & G)
                let t1 = H &+ s1 &+ ch &+ UInt32(Self.k[j]) &+ M[j]

                H = G
                G = F
                F = E
                E = D &+ t1
                D = C
                C = B
                B = A
                A = t1 &+ t2
            }

            hh[0] = (hh[0] &+ A)
            hh[1] = (hh[1] &+ B)
            hh[2] = (hh[2] &+ C)
            hh[3] = (hh[3] &+ D)
            hh[4] = (hh[4] &+ E)
            hh[5] = (hh[5] &+ F)
            hh[6] = (hh[6] &+ G)
            hh[7] = (hh[7] &+ H)
        }

        // produce the final hash value (big-endian) as a 160 bit number:
        var result = Array<UInt8>()
        result.reserveCapacity(hh.count / 4)
        ArraySlice(hh).forEach {
            let item = $0.bigEndian
            let toAppend: [UInt8] = [UInt8(item & 0xff), UInt8((item >> 8) & 0xff), UInt8((item >> 16) & 0xff), UInt8((item >> 24) & 0xff)]
            result += toAppend
        }
        return result
    }

    private func bitPadding(to data: Array<UInt8>, blockSize: Int, allowance: Int = 0) -> Array<UInt8> {
        var tmp = data

        // Step 1. Append Padding Bits
        tmp.append(0x80) // append one bit (UInt8 with one bit) to message

        // append "0" bit until message length in bits ≡ 448 (mod 512)
        var msgLength = tmp.count
        var counter = 0

        while msgLength % blockSize != (blockSize - allowance) {
            counter += 1
            msgLength += 1
        }

        tmp += Array<UInt8>(repeating: 0, count: counter)
        return tmp
    }
}

private extension Collection where Self.Iterator.Element == UInt8, Self.Index == Int {
    func toUInt32Array() -> Array<UInt32> {
        var result = Array<UInt32>()
        result.reserveCapacity(16)
        for idx in stride(from: self.startIndex, to: self.endIndex, by: MemoryLayout<UInt32>.size) {
            var val: UInt32 = 0
            val |= self.count > 3 ? UInt32(self[idx.advanced(by: 3)]) << 24 : 0
            val |= self.count > 2 ? UInt32(self[idx.advanced(by: 2)]) << 16 : 0
            val |= self.count > 1 ? UInt32(self[idx.advanced(by: 1)]) << 8  : 0
            val |= !self.isEmpty ? UInt32(self[idx]) : 0
            result.append(val)
        }

        return result
    }
}

private struct BytesSequence<D: RandomAccessCollection>: Sequence where D.Iterator.Element == UInt8, D.Index == Int {
    let chunkSize: Int
    let data: D

    func makeIterator() -> AnyIterator<D.SubSequence> {
        var offset = data.startIndex
        return AnyIterator {
            let end = Swift.min(self.chunkSize, self.data.count - offset)
            let result = self.data[offset..<offset + end]
            offset = offset.advanced(by: result.count)
            if !result.isEmpty {
                return result
            }
            return nil
        }
    }
}
