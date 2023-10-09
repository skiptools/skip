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
