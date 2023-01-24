import Foundation
import SwiftSyntax

/// Swift source.
public struct Source {
    public let file: File
    public let content: String

    public init(file: File) throws {
        self.file = file
        self.content = try String(contentsOfFile: file.path)

        let contentLines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var currentPosition = 0
        var lines: [(Int, Substring)] = []
        for line in contentLines {
            lines.append((currentPosition, line))
            currentPosition += line.utf8.count + 1 // Add newline
        }
        self.lines = lines
    }

    private let lines: [(offset: Int, line: Substring)]

    /// Return the source line for the given line number, or nil.
    func line(at lineNumber: Int) -> String? {
        guard lineNumber <= lines.count else {
            return nil
        }
        return String(lines[lineNumber - 1].line)
    }

    /// Return the Xcode-compatible range for the given syntax.
    func range(of syntax: SyntaxProtocol) -> Range {
        let startOffset = syntax.positionAfterSkippingLeadingTrivia.utf8Offset
        let length = syntax.contentLength.utf8Length

        let startPosition = position(of: startOffset)
        let endPosition = position(of: startOffset + length - 1) // End of range is inclusive
        return Range(start: startPosition, end: endPosition)
    }

    private func position(of offset: Int) -> Position {
        for entry in lines.enumerated() {
            let lineNumber = entry.offset + 1
            let (lineOffset, _) = entry.element

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
    public struct File {
        public let path: String

        public init?(path: String) {
            guard path.hasSuffix(".swift") && path.count > ".swift".count else {
                return nil
            }
            self.path = path
        }

        public var outputPath: String {
            return path.dropLast(".swift".count) + ".kt"
        }
    }

    /// A line and column-based range in the source, appropriate for Xcode reporting.
    public struct Range: Equatable {
        public let start: Position
        public let end: Position
    }

    /// A line and column-based position in the source, appropriate for Xcode reporting.
    /// Line and column numbers start with 1 rather than 0.
    public struct Position: Equatable, Comparable {
        public let line: Int
        public let column: Int

        public static func < (lhs: Position, rhs: Position) -> Bool {
            return lhs.line < rhs.line || (lhs.line == rhs.line && lhs.column < rhs.column)
        }
    }
}


