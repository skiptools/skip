/// Append an underscore to the end of hard keywords in Kotlin, since they cannot be otherwise escaped.
final class KotlinEscapeKeywordsTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let visitor = EscapeKeywordsVisitor()
        syntaxTree.root.visit(perform: visitor.visit)
    }
}

/// Appends an underscore to the end of hard keywords in Kotlin.
private class EscapeKeywordsVisitor {
    /// https://kotlinlang.org/docs/keyword-reference.html#hard-keywords
    static let hardKeywords: Set<String> = [
        "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "checks", "is", "null", "object", "package", "return", "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while", //"super", // super causes conflicts with the super() call
    ]

    func fixKeyword(name: String) -> String {
        var name = name
        if name.hasPrefix("`") && name .hasSuffix("`") {
            name = name.dropFirst().dropLast().description
        }
        // check against already suffixed keywords, e.g. turn: `null` into `null_`, but also turn `null_` into `null__`
        let unsuffixedName = String(name.reversed().drop(while: { $0 == "_" }).reversed())
        if Self.hardKeywords.contains(unsuffixedName) {
            name = name + "_"
        }
        return name
    }

    func fixParameter<T>(param: Parameter<T>) -> Parameter<T> {
        var p = param
        p.externalLabel = p.externalLabel.map(fixKeyword)
        p._internalLabel = p._internalLabel.map(fixKeyword)
        return p
    }

    func fixLabeledArgument<T>(arg: LabeledValue<T>) -> LabeledValue<T> {
        var a = arg
        a.label = a.label.map(fixKeyword)
        return a
    }

    func fixIdentifierPattern(pattern: IdentifierPattern) -> IdentifierPattern {
        var p = pattern
        p.name = p.name.map(fixKeyword)
        return p
    }

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if let node = node as? KotlinIdentifier {
            node.name = fixKeyword(name: node.name)
        } else if let node = node as? KotlinMemberAccess {
            node.member = fixKeyword(name: node.member)
        } else if let node = node as? KotlinFunctionDeclaration {
            node.parameters = node.parameters.map(fixParameter)
        } else if let node = node as? KotlinFunctionCall {
            node.arguments = node.arguments.map(fixLabeledArgument)
        } else if let node = node as? KotlinVariableDeclaration {
            node.names = node.names.map {
                $0.map(fixKeyword)
            }
        } else if let node = node as? KotlinEnumCaseDeclaration {
            node.caseName = fixKeyword(name: node.name)
            node.associatedValues = node.associatedValues.map(fixParameter)
        } else if let node = node as? KotlinForLoop {
            node.identifierPatterns = node.identifierPatterns.map(fixIdentifierPattern)
        } else if let node = node as? KotlinClosure {
            node.labeledCaptureList = node.labeledCaptureList.map(fixLabeledArgument)
            node.parameters = node.parameters.map(fixParameter)
        }
        return .recurse(nil)
    }
}
