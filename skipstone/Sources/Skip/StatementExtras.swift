import SwiftSyntax

/// Extra directives and trivia derived from the trivia surrounding a statement.
public struct StatementExtras { // Public because part of other public API
    enum Directive {
        /// Insert directly into the output.
        case insert(String, StatementExtras?)
        /// Replace the syntax with the given output.
        case replace(String, StatementExtras?)
        /// Replace the declaration line with the given output.
        case declaration(String)
        /// Mute warnings and errors for this syntax.
        case nowarn
        /// Encountered an invalid directive.
        case invalid(String)
    }

    let directives: [Directive]
    let leadingTrivia: [String]

    /// Process the trivia on the given syntax to parse extras.
    static func process(syntax: Syntax) -> StatementExtras? {
        guard let trivia = syntax.leadingTrivia else {
            return nil
        }

        var directives: [Directive] = []
        var directive: Directive? = nil
        var directiveLines: [String] = []
        var triviaLines: [String] = []
        let insertPrefix = "// SKIP INSERT:"
        let replacePrefix = "// SKIP REPLACE:"
        let declarationPrefix = "// SKIP DECLARE:"
        let noWarnPrefix = "// SKIP NOWARN"
        func endDirective() {
            guard let currentDirective = directive else {
                return
            }
            let directiveString = directiveLines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            switch currentDirective {
            case .insert(_, _):
                let extras = StatementExtras(directives: [], leadingTrivia: triviaLines)
                directives.append(.insert(directiveString, extras))
                triviaLines.removeAll()
            case .replace(_, _):
                let extras = StatementExtras(directives: [], leadingTrivia: triviaLines)
                directives.append(.replace(directiveString, extras))
                triviaLines.removeAll()
            case .declaration(_):
                directives.append(.declaration(directiveString))
            default:
                break
            }
            directive = nil
            directiveLines = []
        }

        var triviaString = trivia.description
        // Drop initial newline that is typically the trailing newline of the preceding statement
        // Drop trailing newline because we add a newline to each line already
        if triviaString.hasPrefix("\n") {
            triviaString = String(triviaString.dropFirst())
        }
        if triviaString.hasSuffix("\n") {
            triviaString = String(triviaString.dropLast())
        }
        let lines = triviaString.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            guard let startIndex = line.firstIndex(where: { !$0.isWhitespace }) else {
                endDirective()
                triviaLines.append("\n")
                continue
            }

            let trimmedLine = String(line[startIndex...])
            if trimmedLine.hasPrefix("// SKIP") {
                endDirective()
                if trimmedLine.hasPrefix(insertPrefix) {
                    directive = .insert("", nil)
                    directiveLines.append(String(trimmedLine.dropFirst(insertPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                } else if trimmedLine.hasPrefix(replacePrefix) {
                    directive = .replace("", nil)
                    directiveLines.append(String(trimmedLine.dropFirst(insertPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                } else if trimmedLine.hasPrefix(declarationPrefix) {
                    directive = .declaration("")
                    directiveLines.append(String(trimmedLine.dropFirst(declarationPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                } else if trimmedLine.hasPrefix(noWarnPrefix) {
                    directives.append(.nowarn)
                } else {
                    directives.append(.invalid(trimmedLine))
                }
                continue
            }
            if directive != nil && trimmedLine.hasPrefix("//") {
                directiveLines.append(trimmedLine.dropFirst(2) + "\n")
            } else {
                endDirective()
                triviaLines.append(trimmedLine + "\n")
            }
        }
        endDirective()

        guard !directives.isEmpty || !triviaLines.isEmpty else {
            return nil
        }
        return StatementExtras(directives: directives, leadingTrivia: triviaLines)
    }

    /// All statements contained in our directives.
    func statements(syntax: Syntax, in syntaxTree: SyntaxTree) -> (statements: [Statement], replace: Bool) {
        var statements: [Statement] = []
        var replace = false
        for directive in directives {
            switch directive {
            case .insert(let string, let extras):
                statements.append(RawStatement(sourceCode: string, syntax: syntax, extras: extras, in: syntaxTree))
            case .replace(let string, let extras):
                replace = true
                statements.append(RawStatement(sourceCode: string, syntax: syntax, extras: extras, in: syntaxTree))
            case .invalid(let string):
                let message = Message(severity: .warning, message: "Unrecognized SKIP comment: \(string)", source: syntaxTree.source, range: syntax.range(in: syntaxTree.source))
                statements.append(MessageStatement(message: message))
            default:
                break
            }
        }
        return (statements, replace)
    }

    /// String to replace statement's declaration.
    var declaration: String? {
        for directive in directives {
            if case .declaration(let string) = directive {
                return string
            }
        }
        return nil
    }

    /// Whether to suppress the statement's message.
    var suppressMessage: Bool {
        for directive in directives {
            if case .nowarn = directive {
                return true
            }
        }
        return false
    }

    /// Leading trivia string, allowing us to preserve original comments and blank lines.
    func leadingTrivia(indentation: Indentation) -> String {
        guard !leadingTrivia.isEmpty else {
            return ""
        }
        let indentationString = indentation.description
        return indentationString + leadingTrivia.joined(separator: indentationString)
    }
}
