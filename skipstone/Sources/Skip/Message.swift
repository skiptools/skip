/// An Xcode-formatted message for the user.
public struct Message: CustomStringConvertible {
    public enum Severity {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    public let file: Source.File?
    public let range: Source.Range?

    init(severity: Severity, message: String, source: Source? = nil, range: Source.Range? = nil) {
        self.severity = severity
        self.message = Self.messageWithSource(for: message, in: source, range: range)
        self.file = source?.file
        self.range = range
    }

    init(severity: Severity, message: String, file: Source.File? = nil, range: Source.Range? = nil) {
        self.severity = severity
        self.message = Self.messageWithSource(for: message, in: nil, range: range)
        self.file = file
        self.range = range
    }

    public var description: String {
        let message = "\(severity == .error ? "error" : "warning"): \(message)"
        guard let file else {
            return message
        }
        guard let range else {
            return "\(file.path): \(message)"
        }
        return "\(file.path):\(range.start.line):\(range.start.column): \(message)"
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
    static func unsupportedSyntax(source: Source? = nil, range: Source.Range? = nil) -> Message {
        return Message(severity: .error, message: "Skip does not support this Swift syntax", source: source, range: range)
    }

    static func untranslatableSyntax(source: Source? = nil, range: Source.Range? = nil) -> Message {
        return Message(severity: .error, message: "Cannot translate this Swift to Kotlin", source: source, range: range)
    }

    static func unsupportedTypeSignature(source: Source? = nil, range: Source.Range? = nil) -> Message {
        return Message(severity: .error, message: "Cannot translate this type signature to Kotlin", source: source, range: range)
    }
}
