import SwiftSyntax

/// Extra directives and trivia derived from the trivia surrounding a statement.
struct StatementExtras {
    enum Directive: Equatable {
        /// Insert directly into the output.
        case insert(String)
        /// Replace the syntax with the given output.
        case replace(String)
        /// Replace the declaration line with the given output.
        case declaration(String)
        /// Mute warnings and errors for this syntax.
        case nowarn
    }

    let directives: [Directive]
    let leadingTrivia: [String]

    static func process(syntax: Syntax) -> StatementExtras? {
        guard let trivia = syntax.leadingTrivia else {
            return nil
        }

        var directives: [Directive] = []
        let insertPrefix = "// SKIP INSERT:"
        let replacePrefix = "// SKIP REPLACE:"
        let declarationPrefix = "// SKIP DECLARE:"
        let noWarnPrefix = "// SKIP NOWARN"
        var isInserting = false
        var isReplacing = false
        var insertionLines: [String] = []
        func endInsertion() {
            if isInserting {
                isInserting = false
                directives.append(.insert(insertionLines.joined(separator: "\n")))
            } else if isReplacing {
                isReplacing = false
                directives.append(.replace(insertionLines.joined(separator: "\n")))
            }
            insertionLines = []
        }

        let lines = trivia.description.split(separator: "\n")
        var triviaLines: [String] = []
        for line in lines {
            var trimmedLine: String
            if let startIndex = line.firstIndex(where: { !$0.isWhitespace }) {
                trimmedLine = String(line[startIndex...])
            } else {
                endInsertion()
                triviaLines.append("")
                continue
            }

            if trimmedLine.hasPrefix(insertPrefix) {
                endInsertion()
                isInserting = true
                trimmedLine = String(trimmedLine.dropFirst(insertPrefix.count))
            } else if trimmedLine.hasPrefix(replacePrefix) {
                endInsertion()
                isReplacing = true
                trimmedLine = String(trimmedLine.dropFirst(replacePrefix.count))
            } else if trimmedLine.hasPrefix(declarationPrefix) {
                endInsertion()
                let declaration = String(trimmedLine.dropFirst(declarationPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                directives.append(.declaration(declaration))
                continue
            } else if trimmedLine.hasPrefix(noWarnPrefix) {
                endInsertion()
                directives.append(.nowarn)
                continue
            }
            if isInserting || isReplacing {
                if trimmedLine.hasPrefix("//") {
                    trimmedLine = String(trimmedLine.dropFirst(2))
                }
                insertionLines.append(trimmedLine)
            } else {
                triviaLines.append(trimmedLine)
            }
        }
        return StatementExtras(directives: directives, leadingTrivia: triviaLines)
    }

    /// All statements contained in our directives.
    func statements(syntax: Syntax, in syntaxTree: SyntaxTree) -> (statements: [Statement], replace: Bool) {
        var statements: [Statement] = []
        var replace = false
        for directive in directives {
            switch directive {
            case .insert(let string):
                statements.append(RawStatement(sourceCode: string, syntax: syntax, extras: self, in: syntaxTree))
            case .replace(let string):
                replace = true
                statements.append(RawStatement(sourceCode: string, syntax: syntax, extras: self, in: syntaxTree))
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

    /// Leading trivia string, allowing us to preserve original comments and blank lines.
    func leadingTrivia(indentation: Indentation) -> String {
        guard !leadingTrivia.isEmpty else {
            return ""
        }
        return indentation.description + leadingTrivia.joined(separator: "\n\(indentation)")
    }
}
