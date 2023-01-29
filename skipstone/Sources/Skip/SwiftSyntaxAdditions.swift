import Foundation
import SwiftSyntax

extension SyntaxProtocol {
    /// Human-readable name of this syntax type.
    public var typeName: String {
        return String(describing: kind)
    }

    /// Pretty-printable tree rooted on this syntax node.
    public var prettyPrintTree: PrettyPrintTree {
        return PrettyPrintVisitor().visit(Syntax(self))
    }

    /// Xcode-compatible range of this syntax in the given source.
    func range(in source: Source) -> Source.Range {
        let offset = positionAfterSkippingLeadingTrivia.utf8Offset
        let length = contentLength.utf8Length
        return source.range(offset: offset, length: length)
    }

    /// Return the source code of this syntax.
    func sourceCode(in source: Source) -> String {
        let offset = positionAfterSkippingLeadingTrivia.utf8Offset
        let length = contentLength.utf8Length
        return source.content(offset: offset, length: length)
    }
}

extension InheritedTypeListSyntax {
    func typeSignatures(in syntaxTree: SyntaxTree) -> ([TypeSignature], Message?) {
        var message: Message? = nil
        let typeSignatures = compactMap { typeSyntax in
            if let typeSignature = TypeSignature.for(syntax: typeSyntax.typeName) {
                return typeSignature
            } else {
                if message == nil {
                    message = .unsupportedTypeSignature(source: syntaxTree.source, range: typeSyntax.range(in: syntaxTree.source))
                }
                return nil
            }
        }
        return (typeSignatures, message)
    }
}

extension FunctionSignatureSyntax {
    func typeSignatures(in syntaxTree: SyntaxTree) -> (TypeSignature?, [Parameter<Statement>], Message?) {
        var returnType: TypeSignature? = nil
        var message: Message? = nil
        if let output = output {
            returnType = TypeSignature.for(syntax: output.returnType)
            if returnType == nil {
                message = .unsupportedTypeSignature(source: syntaxTree.source, range: output.range(in: syntaxTree.source))
            }
        }
        let parameters = input.parameterList.map { parameterSyntax in
            var type: TypeSignature? = nil
            if let typeSyntax = parameterSyntax.type {
                type = TypeSignature.for(syntax: typeSyntax)
                if type == nil {
                    type = .base("Any", [])
                    if message == nil {
                        message = .unsupportedTypeSignature(source: syntaxTree.source, range: typeSyntax.range(in: syntaxTree.source))
                    }
                }
            }
            // TODO: Default value, variadic
            return Parameter<Statement>(externalName: parameterSyntax.firstName?.text ?? "", internalName: parameterSyntax.secondName?.text, type: type)
        }
        return (returnType, parameters, message)
    }
}

private class PrettyPrintVisitor: SyntaxVisitor {
    init() {
        super.init(viewMode: .sourceAccurate)
    }

    func visit(_ node: Syntax) -> PrettyPrintTree {
        let propertyTrees = node.customMirror.children.map { property in
            let valueString = String(describing: property.value)
            let endIndex = valueString.index(valueString.startIndex, offsetBy: 32, limitedBy: valueString.endIndex) ?? valueString.endIndex
            let root = String(valueString[..<endIndex])
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
            return PrettyPrintTree(root: "\(property.label ?? "_"): \(root)")
        }
        let childTrees = node.children(viewMode: .sourceAccurate).map { visit($0) }
        return PrettyPrintTree(root: node.typeName, children: propertyTrees + childTrees)
    }
}

// MARK: - Helper protocols

/// An element in a list of syntaxes (e.g. a list of declarations or statements). These lists, like `MemberDeclListSyntax`
/// and `CodeBlockItemListSyntax`, usually wrap their elements in these containers. This protocol allows us to use them generically.
protocol SyntaxListElement: SyntaxProtocol {
    var content: Syntax { get }
}

/// A syntax that represents a list of elements, e.g. a list of statements or declarations.
protocol SyntaxList: Sequence where Element: SyntaxListElement {
}

/// A syntax that represents a code block. Contains a `SyntaxList` of statements and an end syntax (usually a closing brace) from which to get any final comment.
protocol SyntaxListContainer {
    associatedtype ElementList: SyntaxList
    var syntaxList: ElementList { get }
    var endSyntax: Syntax { get }
}

// MARK: - Conformances

extension SourceFileSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }

    var endSyntax: Syntax {
        return Syntax(self.eofToken)
    }
}

extension CodeBlockItemSyntax: SyntaxListElement {
    var content: Syntax {
        return Syntax(item)
    }
}

extension CodeBlockItemListSyntax: SyntaxList {
}

extension CodeBlockSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }

    var endSyntax: Syntax {
        return Syntax(self.rightBrace)
    }
}

extension MemberDeclListItemSyntax: SyntaxListElement {
    var content: Syntax {
        return Syntax(self.decl)
    }
}

extension MemberDeclListSyntax: SyntaxList {
}

extension MemberDeclBlockSyntax: SyntaxListContainer {
    var syntaxList: MemberDeclListSyntax {
        return self.members
    }

    var endSyntax: Syntax {
        return Syntax(self.rightBrace)
    }
}

extension ClosureExprSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }

    var endSyntax: Syntax {
        return Syntax(self.rightBrace)
    }
}
