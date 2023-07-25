import SwiftSyntax

/// An Xcode-formatted message for the user.
public struct Message: Error, CustomStringConvertible, Codable {
    public enum Kind: String, Codable, Equatable {
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
    static let deprecatedLabel = "This API is deprecated"
    static let unavailableLabel = "This API is not available in Skip"
    static let maybeUnavailableLabel = "Detected possible use of API that is not available in Skip. This may cause errors when converting to Kotlin"

    static func unsupportedSyntax(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support this Swift syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func unsupportedTypeSignature(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support this Swift type syntax [\(syntax.kind)]", source: source, sourceRange: range)
    }

    static func ambiguousFunctionCall(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to disambiguate this function call. Consider differentiating your functions with unique parameter labels", sourceDerived: sourceDerived, source: source)
    }

    static func availabilityMaybeUnavailable(message: String?, sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: message ?? maybeUnavailableLabel, sourceDerived: sourceDerived, source: source)
    }

    static func availabilityUnavailable(message: String?, sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: message ?? unavailableLabel, sourceDerived: sourceDerived, source: source)
    }

    static func availabilityDeprecated(message: String?, sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: message ?? deprecatedLabel, sourceDerived: sourceDerived, source: source)
    }

    static func ifDeclPlacement(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip only supports #if between code block statements or member declarations", source: source, sourceRange: range)
    }

    static func importKindSpecifier(_ sourceDerived: SourceDerived, source: Source? = nil) -> Message {
        return Message(kind: .warning, message: "Skip only supports full module imports", sourceDerived: sourceDerived, source: source)
    }

    static func internalError(_ sourceDerived: SourceDerived, source: Source? = nil) -> Message {
        return Message(kind: .error, message: "Internal error. Please report to Skip support", sourceDerived: sourceDerived, source: source)
    }

    static func genericUnsupportedWhereType(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support the referenced type as a generic constraint", source: source, sourceRange: range)
    }

    static func keyPathUnsupported(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip only supports basic key path expressions consisting of '.'-separated property names", source: source, sourceRange: range)
    }

    static func localFunctionsUniqueIdentifiers(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip requires that nested functions have names which do not conflict with other identifiers within the local scope. Consider giving this function a unique name", sourceDerived: sourceDerived, source: source)
    }

    // Idea: we need to update TypeInferenceEngine to support local type inference
    static func localTypesNotSupported(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .error, message: "Skip does not support type declarations within functions. Consider making this an independent type", sourceDerived: sourceDerived, source: source)
    }

    static func preprocessorTooComplex(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .warning, message: "Skip does not understand complex preprocessor directives. When using Skip-related preprocessor symbols, use only SYMBOL, !SYMBOL, or a list where all symbols are combined by either && or || (but not a combination of the two)", source: source, sourceRange: range)
    }

    // Idea: translate subscripts to Kotlin get/set operator functions
    static func subscriptNotSupported(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .error, message: "Skip does not support custom subscripts. Consider using a standard function", source: source, sourceRange: range)
    }

    static func variableNeedsTypeDeclaration(_ sourceDerived: SourceDerived, source: Source) -> Message {
        return Message(kind: .warning, message: "Skip is unable to determine the type of this expression. Consider declaring the variable type explicitly, i.e. 'var v: <Type> = ...'", sourceDerived: sourceDerived, source: source)
    }

    static func variadicParameterLabel(_ syntax: SyntaxProtocol, source: Source) -> Message {
        let range = syntax.range(in: source)
        return Message(kind: .warning, message: "Skip may not be able to properly match calls to this function. Add an external label to any parameter that follows a variadic parameter", source: source, sourceRange: range)
    }
}
