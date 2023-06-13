import SwiftSyntax

/// Extra directives and trivia derived from the trivia surrounding a statement.
struct StatementExtras {
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
        /// Marker for a file whose purpose is to provide Swift symbols for separate Kotlin code. Symbols files are not transpiled, and warnings are suppressed.
        case symbolFile
    }

    let directives: [Directive]
    let leadingTrivia: [String]
    let trailingTrivia: [String]

    /// Extras consisting of a single leading new line, as is commonly used to separate type and function declarations.
    static let singleNewline = StatementExtras(directives: [], leadingTrivia: ["\n"], trailingTrivia: [])

    /// Decode the trivia on the given syntax to parse extras.
    static func decode(syntax: SyntaxProtocol) -> StatementExtras? {
        let trailingTriviaString = processTrailingTrivia(syntax: syntax)
        var directives: [Directive] = []
        var directive: Directive? = nil
        var directiveLines: [String] = []
        var triviaLines: [String] = []
        var isMultilineCommentDirective = false
        var multilineCommentDirectiveIndentation = 0
        let insertPrefix = "SKIP INSERT:"
        let replacePrefix = "SKIP REPLACE:"
        let declarationPrefix = "SKIP DECLARE:"
        let noWarnPrefix = "SKIP NOWARN"
        let symbolFilePrefix = "SKIP SYMBOLFILE"
        func endDirective() {
            guard let currentDirective = directive else {
                return
            }
            let directiveString = directiveLines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            switch currentDirective {
            case .insert:
                let extras = StatementExtras(directives: [], leadingTrivia: triviaLines, trailingTrivia: [])
                directives.append(.insert(directiveString, extras))
                triviaLines.removeAll()
            case .replace:
                let extras = StatementExtras(directives: [], leadingTrivia: triviaLines, trailingTrivia: [])
                directives.append(.replace(directiveString, extras))
                triviaLines.removeAll()
            case .declaration:
                directives.append(.declaration(directiveString))
            default:
                break
            }
            directive = nil
            directiveLines = []
            isMultilineCommentDirective = false
        }

        var triviaString = syntax.leadingTrivia.description
        // Drop initial newline that is typically the trailing newline of the preceding statement
        if triviaString.hasPrefix("\n") {
            triviaString = String(triviaString.dropFirst())
        }
        while !triviaString.isEmpty {
            // Do our own line splits so that we can differentiate whether the last line had a trailing newline.
            // We don't want to treat indentation before the statement as a trivia line
            let line: String
            let hasNewline: Bool
            if let nextNewline = triviaString.firstIndex(of: "\n") {
                line = String(triviaString[..<nextNewline])
                hasNewline = true
                triviaString = String(triviaString.dropFirst(line.count + 1))
            } else {
                line = triviaString
                hasNewline = false
                triviaString = ""
            }

            var trimmedLine = line.trimmingCharacters(in: .whitespaces)
            var isDirective = false
            var isSingleLineDirective = false
            if isMultilineCommentDirective {
                if trimmedLine == "*/" {
                    endDirective()
                    if hasNewline {
                        triviaLines.append("\n")
                    }
                    continue
                } else if trimmedLine.isEmpty {
                    if hasNewline {
                        directiveLines.append("\n")
                    }
                    continue
                } else {
                    let firstNonWhitespaceIndex = line.firstIndex(where: { !$0.isWhitespace })!
                    let leadingWhitespaceCount = line.distance(from: line.startIndex, to: firstNonWhitespaceIndex)
                    let trailingWhitespaceCount = line.count - trimmedLine.count - leadingWhitespaceCount
                    trimmedLine = String(line.dropFirst(min(multilineCommentDirectiveIndentation, leadingWhitespaceCount)).dropLast(trailingWhitespaceCount))
                }
            } else if trimmedLine.isEmpty {
                endDirective()
                if hasNewline {
                    triviaLines.append("\n")
                }
                continue
            } else {
                if trimmedLine.hasPrefix("/* SKIP") {
                    isDirective = true
                    trimmedLine.removeFirst(3)
                    if trimmedLine.hasSuffix("*/") {
                        isSingleLineDirective = true
                        trimmedLine.removeLast(2)
                    } else {
                        isMultilineCommentDirective = true
                        multilineCommentDirectiveIndentation = line.distance(from: line.startIndex, to: line.firstIndex(of: "/")!)
                    }
                } else if trimmedLine.hasPrefix("// SKIP") {
                    isDirective = true
                    trimmedLine.removeFirst(3)
                }
            }

            if isDirective {
                endDirective()
                if trimmedLine.hasPrefix(insertPrefix) {
                    directive = .insert("", nil)
                    directiveLines.append(String(trimmedLine.dropFirst(insertPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                } else if trimmedLine.hasPrefix(replacePrefix) {
                    directive = .replace("", nil)
                    directiveLines.append(String(trimmedLine.dropFirst(replacePrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                } else if trimmedLine.hasPrefix(declarationPrefix) {
                    directive = .declaration("")
                    directiveLines.append(String(trimmedLine.dropFirst(declarationPrefix.count)).trimmingCharacters(in: .whitespaces) + "\n")
                } else if trimmedLine.hasPrefix(noWarnPrefix) {
                    directives.append(.nowarn)
                    isSingleLineDirective = isSingleLineDirective || !isMultilineCommentDirective
                } else if trimmedLine.hasPrefix(symbolFilePrefix) {
                    directives.append(.symbolFile)
                    isSingleLineDirective = isSingleLineDirective || !isMultilineCommentDirective
                } else {
                    directives.append(.invalid(trimmedLine))
                    isSingleLineDirective = isSingleLineDirective || !isMultilineCommentDirective
                }
                if isSingleLineDirective {
                    endDirective()
                }
            } else if directive != nil && (isMultilineCommentDirective || trimmedLine.hasPrefix("// ")) {
                if trimmedLine.hasPrefix("// ") {
                    directiveLines.append(trimmedLine.dropFirst(3) + "\n")
                } else {
                    directiveLines.append(trimmedLine + "\n")
                }
            } else {
                endDirective()
                triviaLines.append(trimmedLine + "\n")
            }
        }
        endDirective()

        guard !directives.isEmpty || !triviaLines.isEmpty || !trailingTriviaString.isEmpty else {
            return nil
        }
        return StatementExtras(directives: directives, leadingTrivia: triviaLines, trailingTrivia: [trailingTriviaString])
    }

    private static func processTrailingTrivia(syntax: SyntaxProtocol) -> String {
        syntax.trailingTrivia.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// All statements contained in our directives.
    func statements(syntax: SyntaxProtocol, in syntaxTree: SyntaxTree) -> (statements: [Statement], replace: Bool) {
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
                let message = Message(kind: .warning, message: "Unrecognized SKIP comment: \(string)", source: syntaxTree.source, sourceRange: syntax.range(in: syntaxTree.source))
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

    /// Whether the symbol file directive is present.
    var isSymbolFile: Bool {
        for directive in directives {
            if case .symbolFile = directive {
                return true
            }
        }
        return false
    }

    /// Whether to suppress the statement's messages.
    var suppressMessages: Bool {
        for directive in directives {
            if case .nowarn = directive {
                return true
            }
        }
        return false
    }

    /// Leading trivia string, allowing us to preserve original comments and blank lines.
    func leadingTrivia(indentation: Indentation) -> String {
        return join(lines: leadingTrivia, indentation: indentation)
    }

    /// Trailing trivia string, allowing us to preserve trailing comments.
    func trailingTrivia(indentation: Indentation) -> String {
        return join(lines: trailingTrivia, indentation: indentation, indentFirstLine: false)
    }

    private func join(lines: [String], indentation: Indentation, indentFirstLine: Bool = true) -> String {
        guard !lines.isEmpty else {
            return ""
        }
        var joined = ""
        let indentationString = indentation.description
        for (index, string) in lines.enumerated() {
            if string == "\n" || (!indentFirstLine && index == 0) {
                joined.append(string)
            } else {
                joined.append(indentationString)
                joined.append(string)
            }
        }
        return joined
    }
}
