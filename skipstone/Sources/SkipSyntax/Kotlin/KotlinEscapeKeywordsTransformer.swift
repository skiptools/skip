/// Append an underscore to the end of hard keywords in Kotlin, since they cannot be otherwise escaped.
class KotlinEscapeKeywordsTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        let visitor = EscapeKeywordsVisitor()
        syntaxTree.root.visit(perform: visitor.visit)
    }
}

/// Appends an underscore to the end of hard keywords in Kotlin.
private class EscapeKeywordsVisitor {
    /// https://kotlinlang.org/docs/keyword-reference.html#hard-keywords
    static let hardKeywords: Set<String> = [
        "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is", "checks", "is", "null", "object", "package", "return", "this", "throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while", //"super", // super causes conflicts with the super() call
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

    func fixParameter(param: Parameter<KotlinExpression>) -> Parameter<KotlinExpression> {
        var p = param
        p.externalLabel = p.externalLabel.map(fixKeyword)
        p._internalLabel = p._internalLabel.map(fixKeyword)
        return p
    }

    func fixArgument(arg: LabeledValue<KotlinExpression>) -> LabeledValue<KotlinExpression> {
        var a = arg
        a.label = a.label.map(fixKeyword)
        return a
    }

    func visit(_ node: KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode> {
        if let node = node as? KotlinEnumCaseDeclaration {
            node.name = fixKeyword(name: node.name)
        } else if let node = node as? KotlinIdentifier {
            node.name = fixKeyword(name: node.name)
        } else if let node = node as? KotlinMemberAccess {
            node.member = fixKeyword(name: node.member)
        } else if let node = node as? KotlinFunctionDeclaration {
            node.parameters = node.parameters.map(fixParameter)
        } else if let node = node as? KotlinFunctionCall {
            node.arguments = node.arguments.map(fixArgument)
        } else if let node = node as? KotlinVariableDeclaration {
            node.names = node.names.map {
                $0.map(fixKeyword)
            }
        }
        return .recurse(nil)
    }
}
