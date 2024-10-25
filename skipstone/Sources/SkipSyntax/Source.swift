import Foundation
import SwiftSyntax

/// Swift or Kotlin source code file.
public struct Source : Encodable {
    public let file: FilePath
    public let content: String

    public init(file: FilePath) throws {
        let content = try String(contentsOfFile: file.path)
        self = Source(file: file, content: content)
    }

    public init(file: FilePath, content: String) {
        self.file = file
        self.content = content
        let contentLines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var currentPosition = 0
        var lines: [SourceLine] = []
        for line in contentLines {
            lines.append(SourceLine(offset: currentPosition, line: line.description))
            currentPosition += line.utf8.count + 1 // Add newline
        }
        self.lines = lines
    }

    struct SourceLine : Encodable {
        let offset: Int
        let line: String
    }

    private let lines: [SourceLine]

    /// Return the source line for the given line number, or nil.
    func line(at lineNumber: Int) -> String? {
        guard lineNumber <= lines.count else {
            return nil
        }
        return String(lines[lineNumber - 1].line)
    }

    /// Return an Xcode-compatible range for the given UTF8 offsets.
    func range(offset: Int, length: Int) -> Range {
        let startPosition = position(of: offset)
        let endPosition = position(of: offset + length - 1) // End of range is inclusive
        return Range(start: startPosition, end: endPosition)
    }

    /// Return the content for the given UTF8 offsets.
    func content(offset: Int, length: Int) -> String {
        let utf8 = content.utf8
        let startIndex = utf8.index(utf8.startIndex, offsetBy: offset)
        let endIndex = utf8.index(utf8.startIndex, offsetBy: offset + length)
        return String(utf8[startIndex..<endIndex]) ?? ""
    }

    private func position(of offset: Int) -> Position {
        for entry in lines.enumerated() {
            let lineNumber = entry.offset + 1
            let lineOffset = entry.element.offset

            let nextLineOffset = lineNumber >= lines.count ? Int.max : lines[entry.offset + 1].offset
            if nextLineOffset > offset {
                // Next line is past, so must be this line
                let columnNumber = max(1, offset - lineOffset + 1)
                return Position(line: lineNumber, column: columnNumber)
            }
        }
        return Position(line: 1, column: 1)
    }

    /// A Swift source file.
    ///
    /// - Note: `Codable` for use in `CodebaseInfo`.
    public struct FilePath: Hashable, Codable {
        public private(set) var path: String
        /// The suffix of a file that indicates it is a bridging file
        private static let bridgeFileSuffix = "_Bridge.swift"

        public init(path: String) {
            self.path = path
        }

        public var name: String {
            get {
                guard path.last != "/", let lastDirIndex = path.lastIndex(of: "/") else {
                    return path
                }
                return String(path[path.index(after: lastDirIndex)...])
            }
            set {
                let withoutName = path.dropLast(name.count)
                path = withoutName + newValue
            }
        }

        public var `extension`: String {
            get {
                guard let dotIndex = path.lastIndex(of: ".") else {
                    return ""
                }
                return String(path[path.index(after: dotIndex)...])
            }
            set {
                var path = self.path
                if let dotIndex = path.lastIndex(of: ".") {
                    path = String(path[..<dotIndex])
                }
                self.path = newValue.isEmpty ? path : path + "." + newValue
            }
        }

        public func outputFile(withExtension: String) -> Source.FilePath {
            var output = self
            output.extension = withExtension
            return output
        }

        /// The corresponding Swift file.
        public var swiftOutputFile: Source.FilePath? {
            guard self.extension == "swift" else {
                return nil
            }
            return outputFile(withExtension: "swift")
        }

        /// The corresponding Swift file for bridging output.
        public var bridgeOutputFile: Source.FilePath? {
            guard self.extension == "swift" else {
                return nil
            }
            return Source.FilePath(path: self.path.dropLast(".swift".count) + Self.bridgeFileSuffix)
        }

        /// The source Swift file that corresponds to this bridge file, if it is a bridge.
        public var bridgelessOutputFile: Source.FilePath? {
            if !isBridgeOutputFile {
                return nil
            }
            return Source.FilePath(path: self.path.dropLast(Self.bridgeFileSuffix.count) + ".swift")
        }

        /// Whether this is a bridging output file.
        public var isBridgeOutputFile: Bool {
            return path.hasSuffix(Self.bridgeFileSuffix)
        }
    }

    /// A line and column-based range in the source, appropriate for Xcode reporting.
    public struct Range: Equatable, Codable {
        public let start: Position
        public let end: Position

        public init(start: Position, end: Position) {
            self.start = start
            self.end = end
        }
    }

    /// A line and column-based position in the source, appropriate for Xcode reporting.
    /// Line and column numbers start with 1 rather than 0.
    public struct Position: Equatable, Comparable, Codable {
        public let line: Int
        public let column: Int

        public init(line: Int, column: Int) {
            self.line = line
            self.column = column
        }
        
        public static func < (lhs: Position, rhs: Position) -> Bool {
            return lhs.line < rhs.line || (lhs.line == rhs.line && lhs.column < rhs.column)
        }
    }
}
