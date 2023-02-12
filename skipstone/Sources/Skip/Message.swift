import SwiftSyntax

/// An Xcode-formatted message for the user.
public struct Message: Error, CustomStringConvertible {
    public enum Severity {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    public let sourceFile: Source.File?
    public let sourceRange: Source.Range?

    init(severity: Severity, message: String, source: Source? = nil, sourceRange: Source.Range? = nil) {
        self.severity = severity
        self.message = Self.messageWithSource(for: message, in: source, range: sourceRange)
        self.sourceFile = source?.file
        self.sourceRange = sourceRange
    }

    init(severity: Severity, message: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) {
        self.severity = severity
        self.message = Self.messageWithSource(for: message, in: nil, range: sourceRange)
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    init(severity: Severity, message: String, sourceDerived: SourceDerived) {
        self = Message(severity: severity, message: message, sourceFile: sourceDerived.sourceFile, sourceRange: sourceDerived.sourceRange)
    }

    public var description: String {
        let message = "\(severity == .error ? "error" : "warning"): \(message)"
        guard let sourceFile else {
            return message
        }
        guard let sourceRange else {
            return "\(sourceFile.path): \(message)"
        }
        return "\(sourceFile.path):\(sourceRange.start.line):\(sourceRange.start.column): \(message)"
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
        return Message(severity: .error, message: "Skip does not support this Swift syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func unsupportedTypeSignature(_ typeSyntax: TypeSyntax, source: Source? = nil, sourceRange: Source.Range? = nil) -> Message {
        var range = sourceRange
        if range == nil, let source {
            range = typeSyntax.range(in: source)
        }
        return Message(severity: .error, message: "Skip does not support this Swift type syntax [\(typeSyntax.kind)]", source: source, sourceRange: range)
    }

    static func ambiguousFunctionCall(sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) -> Message {
        return Message(severity: .warning, message: "Skip is unable to disambiguate this function call. Consider adding explicit types to the values supplied as arguments", sourceFile: sourceFile, sourceRange: sourceRange)
    }

    static func unknownMemberBaseType(member: String, sourceFile: Source.File? = nil, sourceRange: Source.Range? = nil) -> Message {
        return Message(severity: .error, message: "Skip is unable to determine the owning type for member '\(member)'", sourceFile: sourceFile, sourceRange: sourceRange)
    }
}
