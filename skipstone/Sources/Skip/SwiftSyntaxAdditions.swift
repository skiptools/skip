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
    /// The list of types in this list, and optional messages warning of any issues.
    func typeSignatures(in syntaxTree: SyntaxTree) -> ([TypeSignature], [Message]) {
        var messages: [Message] = []
        let typeSignatures = compactMap { typeSyntax in
            let typeSignature = TypeSignature.for(syntax: typeSyntax.typeName)
            if typeSignature != .none {
                return typeSignature
            } else {
                messages.append(.unsupportedTypeSignature(typeSyntax.typeName, source: syntaxTree.source, sourceRange: typeSyntax.range(in: syntaxTree.source)))
                return nil
            }
        }
        return (typeSignatures, messages)
    }
}

extension FunctionSignatureSyntax {
    /// The return type and parameters in this signature, and optional messages warning of any issues.
    func typeSignatures(in syntaxTree: SyntaxTree) -> (TypeSignature, [Parameter<Statement>], [Message]) {
        var returnType: TypeSignature = .none
        var messages: [Message] = []
        if let output = output {
            returnType = TypeSignature.for(syntax: output.returnType)
            if returnType == .none {
                returnType = .void
                messages.append(.unsupportedTypeSignature(output.returnType, source: syntaxTree.source, sourceRange: output.range(in: syntaxTree.source)))
            }
        }
        let parameters = input.parameterList.map { parameterSyntax in
            var type: TypeSignature = .none
            if let typeSyntax = parameterSyntax.type {
                type = TypeSignature.for(syntax: typeSyntax)
                if type == .none {
                    type = .any
                    messages.append(.unsupportedTypeSignature(typeSyntax, source: syntaxTree.source, sourceRange: typeSyntax.range(in: syntaxTree.source)))
                }
            }
            let isVariadic = parameterSyntax.ellipsis?.text == "..."
            var defaultValue: Statement? = nil
            if let defaultArgument = parameterSyntax.defaultArgument {
                defaultValue = StatementDecoder.decode(syntax: defaultArgument, in: syntaxTree).first
            }
            return Parameter<Statement>(externalName: parameterSyntax.firstName?.text ?? "", internalName: parameterSyntax.secondName?.text, declaredType: type, isVariadic: isVariadic, defaultValue: defaultValue)
        }
        return (returnType, parameters, messages)
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
    var content: SyntaxProtocol { get }
}

/// A syntax that represents a list of elements, e.g. a list of statements or declarations.
protocol SyntaxList: Sequence where Element: SyntaxListElement {
}

/// A syntax that represents a code block. Contains a `SyntaxList` of statements and an end syntax (usually a closing brace) from which to get any final comment.
protocol SyntaxListContainer {
    associatedtype ElementList: SyntaxList
    var syntaxList: ElementList { get }
}

// MARK: - Conformances

extension SourceFileSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }
}

extension CodeBlockItemSyntax: SyntaxListElement {
    var content: SyntaxProtocol {
        return item
    }
}

extension CodeBlockItemListSyntax: SyntaxList {
}

extension CodeBlockSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }
}

extension MemberDeclListItemSyntax: SyntaxListElement {
    var content: SyntaxProtocol {
        return self.decl
    }
}

extension MemberDeclListSyntax: SyntaxList {
}

extension MemberDeclBlockSyntax: SyntaxListContainer {
    var syntaxList: MemberDeclListSyntax {
        return self.members
    }
}

extension ClosureExprSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }
}
