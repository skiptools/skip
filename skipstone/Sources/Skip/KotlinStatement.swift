/// A node in the Kotlin syntax tree.
protocol KotlinStatement {
    /// The corresponding range in the Swift source.
    var sourceRange: Source.Range? { get }

    /// Kotlin source code. May be empty.
    func code(indentation: Indentation) -> String

    /// Messages about this statement and its children.
    var messages: [Message] { get }
}

extension KotlinStatement {
    var sourceRange: Source.Range? {
        return nil
    }
}

extension KotlinStatement where Self: Statement {
    var sourceRange: Source.Range? {
        return range
    }
}

extension ImportDeclaration: KotlinStatement {
    func code(indentation: Indentation) -> String {
        return "\(indentation)import \(moduleName)"
    }
}

extension RawStatement: KotlinStatement {
    func code(indentation: Indentation) -> String {
        return "\(indentation)\(sourceCode)"
    }
}

extension MessageStatement: KotlinStatement {
    func code(indentation: Indentation) -> String {
        return ""
    }
}
