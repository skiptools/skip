import SwiftSyntax

/// An Xcode-formatted message for the user.
public struct Message: Error, CustomStringConvertible, Encodable {
    public enum Kind: String, Encodable, Equatable {
        /// A trace-level statement that will only be emitted in debug mode
        case trace
        case note // SwiftSyntax.DiagnosticSeverity.note
        case warning // SwiftSyntax.DiagnosticSeverity.warning
        case error // SwiftSyntax.DiagnosticSeverity.error
    }

    public let kind: Kind
    public let message: String
    public let sourceFile: Source.FilePath?
    public let sourceRange: Source.Range?

    init(kind: Kind, message: String, source: Source? = nil, sourceRange: Source.Range? = nil) {
        self.kind = kind
        self.message = Self.messageWithSource(for: message, in: source, range: sourceRange)
        self.sourceFile = source?.file
        self.sourceRange = sourceRange
    }

    public init(kind: Kind, message: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.kind = kind
        self.message = Self.messageWithSource(for: message, in: nil, range: sourceRange)
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    init(kind: Kind, message: String, sourceDerived: SourceDerived, source: Source? = nil) {
        self.kind = kind
        self.message = Self.messageWithSource(for: message, in: source, range: sourceDerived.sourceRange)
        self.sourceFile = sourceDerived.sourceFile ?? source?.file
        self.sourceRange = sourceDerived.sourceRange
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
    static func unsupportedSyntax(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support this Swift syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func unsupportedTypeSignature(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support this Swift type syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func ambiguousFunctionCall(sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to disambiguate this function call. Consider differentiating your functions with unique parameter labels", sourceDerived: sourceDerived, source: source)
    }

    static func ifDeclPlacement(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip only supports #if between code block statements or member declarations", source: source, sourceRange: range)
    }

    static func genericUnsupportedWhereType(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support the referenced type as a generic constraint", source: source, sourceRange: range)
    }

    static func localFunctionsNotSupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support nested functions. Consider making this an independent function", sourceDerived: sourceDerived, source: source)
    }

    static func localTypesNotSupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support type declarations within functions. Consider making this an independent type", sourceDerived: sourceDerived, source: source)
    }

    static func subscriptNotSupported(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support custom subscripts. Consider using a standard function", source: source, sourceRange: range)
    }

    static func variableNeedsTypeDeclaration(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to determine the type of this expression. Consider declaring the variable type explicitly, i.e. 'var v: <Type> = ...'", sourceDerived: sourceDerived, source: source)
    }
}
