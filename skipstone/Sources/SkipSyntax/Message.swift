import SwiftSyntax

/// An Xcode-formatted message for the user.
public struct Message: Error, CustomStringConvertible, Encodable {
    public enum Kind: String, Encodable, Equatable {
        /// A trace-level statement that will only be emitted in debug mode
        case trace
        case note
        case warning
        case error
    }

    public let kind: Kind
    public let message: String
    public let sourceFile: Source.File?
    public let sourceRange: Source.Range?

    init(kind: Kind, message: String, source: Source? = nil, sourceRange: Source.Range? = nil) {
        self.kind = kind
        self.message = Self.messageWithSource(for: message, in: source, range: sourceRange)
        self.sourceFile = source?.file
        self.sourceRange = sourceRange
    }

    public init(kind: Kind, message: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.kind = kind
        self.message = Self.messageWithSource(for: message, in: nil, range: sourceRange)
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    init(kind: Kind, message: String, sourceDerived: SourceDerived) {
        self = Message(kind: kind, message: message, sourceFile: sourceDerived.sourceFile, sourceRange: sourceDerived.sourceRange)
    }

    public var description: String {
        let messageString = "\(kind.rawValue): \(message)"
        guard let sourceFile else {
            return messageString
        }
        guard let sourceRange else {
            return "\(sourceFile.path): \(messageString)"
        }
        return "\(sourceFile.path):\(sourceRange.start.line):\(sourceRange.start.column): \(messageString)"
    }

    private static func messageWithSource(for message: String, in source: Source?, range: Source.Range?) -> String {
        guard let source, let range, let line = source.line(at: range.start.line) else {
            return message
        }
        guard range.start.column <= line.count else {
            return "\(message)\n\(line)"
        }

        let startColumn = range.start.column
        let endColumn = (range.end.line == range.start.line) ? min(line.count, range.end.column) : line.count

        let characters = line.map { $0 }
        var underline = ""
        for i in 1..<startColumn {
            if characters[i - 1] == "\t" {
                underline.append("\t")
            } else {
                underline.append(" ")
            }
        }
        underline.append("^")
        underline.append(String(repeating: "~", count: max(0, endColumn - startColumn)))
        return "\(message)\n\(line)\n\(underline)"
    }
}

extension Message {
    static func unsupportedSyntax(_ syntax: SyntaxProtocol, source: Source? = nil, sourceRange: Source.Range? = nil) -> Message {
        var range = sourceRange
        if range == nil, let source {
            range = syntax.range(in: source)
        }
        return Message(kind: .error, message: "Skip does not support this Swift syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func unsupportedTypeSignature(_ syntax: SyntaxProtocol, source: Source? = nil, sourceRange: Source.Range? = nil) -> Message {
        var range = sourceRange
        if range == nil, let source {
            range = syntax.range(in: source)
        }
        return Message(kind: .error, message: "Skip does not support this Swift type syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func ambiguousFunctionCall(sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) -> Message {
        return Message(kind: .warning, message: "Skip is unable to disambiguate this function call. Consider adding explicit types to the values supplied as arguments", sourceFile: sourceFile, sourceRange: sourceRange)
    }

    static func genericUnsupportedWhereType(_ syntax: SyntaxProtocol, source: Source? = nil, sourceRange: Source.Range? = nil) -> Message {
        var range = sourceRange
        if range == nil, let source {
            range = syntax.range(in: source)
        }
        return Message(kind: .error, message: "Skip does not support the referenced type as a generic constraint", source: source, sourceRange: range)
    }

    static func genericWhereNameMismatch(_ syntax: SyntaxProtocol, source: Source? = nil, sourceRange: Source.Range? = nil) -> Message {
        var range = sourceRange
        if range == nil, let source {
            range = syntax.range(in: source)
        }
        return Message(kind: .error, message: "Skip is not able to match this where constraint to a declared generic type", source: source, sourceRange: range)
    }
}
