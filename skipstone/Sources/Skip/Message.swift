/// An Xcode-formatted message for the user.
public struct Message: CustomStringConvertible {
    public enum Severity {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String
    public let sourceFile: Source.File
    public let range: Source.Range

    init(severity: Severity, message: String, source: Source, range: Source.Range) {
        self.severity = severity
        self.message = Self.messageWithSource(for: message, in: source, range: range)
        self.sourceFile = source.file
        self.range = range
    }

    public var description: String {
        return "\(sourceFile.path):\(range.start.line):\(range.start.column): \(severity == .error ? "error" : "warning"): \(message)"
    }

    private static func messageWithSource(for message: String, in source: Source, range: Source.Range) -> String {
        guard let line = source.line(at: range.start.line) else {
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
