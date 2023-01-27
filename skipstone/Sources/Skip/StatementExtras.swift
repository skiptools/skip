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

    /// Process the trivia on the given syntax to parse extras.
    static func process(syntax: Syntax) -> StatementExtras? {
        guard let trivia = syntax.leadingTrivia else {
            return nil
        }

        var directives: [Directive] = []
        var directive: Directive? = nil
        var directiveLines: [String] = []
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
            case .insert(_):
                directives.append(.insert(directiveString))
            case .replace(_):
                directives.append(.replace(directiveString))
            case .declaration(_):
                directives.append(.declaration(directiveString))
            default:
                break
            }
            directive = nil
            directiveLines = []
        }

        let lines = trivia.description.split(separator: "\n", omittingEmptySubsequences: false)
        var triviaLines: [String] = []
        var isFirstLine = true
        for line in lines {
            guard let startIndex = line.firstIndex(where: { !$0.isWhitespace }) else {
                if isFirstLine {
                    // Ignore an initial blank line because it is the trailing newline from the previous syntax
                    isFirstLine = false
                } else {
                    endDirective()
                    triviaLines.append("\n")
                }
                continue
            }

            var trimmedLine = String(line[startIndex...])
            if trimmedLine.hasPrefix(insertPrefix) {
                endDirective()
                directive = .insert("")
                directiveLines.append(String(trimmedLine.dropFirst(insertPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                continue
            } else if trimmedLine.hasPrefix(replacePrefix) {
                endDirective()
                directive = .replace("")
                directiveLines.append(String(trimmedLine.dropFirst(insertPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                continue
            } else if trimmedLine.hasPrefix(declarationPrefix) {
                endDirective()
                directive = .declaration("")
                directiveLines.append(String(trimmedLine.dropFirst(declarationPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                continue
            } else if trimmedLine.hasPrefix(noWarnPrefix) {
                endDirective()
                directives.append(.nowarn)
                continue
            }
            if directive != nil {
                if trimmedLine.hasPrefix("//") {
                    trimmedLine = String(trimmedLine.dropFirst(2))
                    directiveLines.append(trimmedLine + "\n")
                } else {
                    endDirective()
                    triviaLines.append(trimmedLine + "\n")
                }
            } else {
                triviaLines.append(trimmedLine + "\n")
            }
        }
        endDirective()
        
        // Remove any trailing blank line, as it represents the last empty subsequence of our split
        if triviaLines.last == "\n" {
            //~~~triviaLines = Array(triviaLines.dropLast())
        }
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
        let indentationString = indentation.description
        return indentationString + leadingTrivia.joined(separator: indentationString)
    }
}
