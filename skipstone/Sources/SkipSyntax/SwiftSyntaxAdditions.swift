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
        let length = trimmedLength.utf8Length
        return source.range(offset: offset, length: length)
    }
}

extension InheritedTypeListSyntax {
    /// The list of types in this list, and optional messages warning of any issues.
    func typeSignatures(in syntaxTree: SyntaxTree) -> ([TypeSignature], [Message]) {
        var messages: [Message] = []
        let typeSignatures = compactMap { typeSyntax in
            let typeSignature = TypeSignature.for(syntax: typeSyntax.type, in: syntaxTree)
            if typeSignature != .none {
                return typeSignature
            } else {
                messages.append(.unsupportedTypeSignature(typeSyntax.type, source: syntaxTree.source))
                return nil
            }
        }
        return (typeSignatures, messages)
    }
}

extension FunctionSignatureSyntax {
    /// The return type and parameters in this signature, and optional messages warning of any issues.
    func typeSignatures(in syntaxTree: SyntaxTree) -> (TypeSignature, [Parameter<Expression>], [Message]) {
        var messages: [Message] = []
        let returnType = returnClause?.typeSignature(in: syntaxTree, messages: &messages) ?? .void
        let parameters = parameterClause.parameters(in: syntaxTree, messages: &messages)
        return (returnType, parameters, messages)
    }
}

extension ReturnClauseSyntax {
    fileprivate func typeSignature(in syntaxTree: SyntaxTree, messages: inout [Message]) -> TypeSignature {
        var signature = TypeSignature.for(syntax: type, in: syntaxTree)
        if signature == .none {
            signature = .void
            messages.append(.unsupportedTypeSignature(type, source: syntaxTree.source))
        }
        return signature
    }
}

extension Parameter<Expression> {
    fileprivate init(firstName: String?, secondName: String?, typeSyntax: TypeSyntax?, ellipses: String? = nil, defaultArgument: InitializerClauseSyntax? = nil, in syntaxTree: SyntaxTree, messages: inout [Message]) {
        var type: TypeSignature = .none
        var isInOut = false
        var attributes: Attributes? = nil
        if let typeSyntax {
            type = TypeSignature.for(syntax: typeSyntax, in: syntaxTree)
            if type == .none {
                type = .any
                messages.append(.unsupportedTypeSignature(typeSyntax, source: syntaxTree.source))
            }
            isInOut = TypeSignature.isInOut(syntax: typeSyntax)
            attributes = TypeSignature.attributes(syntax: typeSyntax, in: syntaxTree)
        }
        let isVariadic = ellipses == "..."
        var defaultValue: Expression? = nil
        if let defaultArgument {
            defaultValue = ExpressionDecoder.decode(syntax: defaultArgument.value, in: syntaxTree)
        }
        self = Parameter<Expression>(externalLabel: firstName, internalLabel: secondName, declaredType: type, isInOut: isInOut, isVariadic: isVariadic, attributes: attributes ?? Attributes(), defaultValue: defaultValue)
    }
}

extension ParameterClauseSyntax {
    func parameters(in syntaxTree: SyntaxTree) -> ([Parameter<Expression>], [Message]) {
        var messages: [Message] = []
        let parameters = parameters(in: syntaxTree, messages: &messages)
        return (parameters, messages)
    }

    fileprivate func parameters(in syntaxTree: SyntaxTree, messages: inout [Message]) -> [Parameter<Expression>] {
        let parameters = parameters.map { parameterSyntax in
            Parameter<Expression>(firstName: parameterSyntax.firstName.text, secondName: parameterSyntax.secondName?.text, typeSyntax: parameterSyntax.type, ellipses: parameterSyntax.ellipsis?.text, defaultArgument: parameterSyntax.defaultArgument, in: syntaxTree, messages: &messages)
        }
        for (index, parameter) in parameters.enumerated() {
            if parameter.externalLabel == nil && index > 0 && parameters[index - 1].isVariadic {
                messages.append(.variadicParameterLabel(self.parameters, source: syntaxTree.source))
            }
        }
        return parameters
    }
}

extension AccessorBlockSyntax {
    func accessors(in syntaxTree: SyntaxTree) -> Accessors {
        var accessors = Accessors()
        for accessorSyntax in self.accessors {
            if accessorSyntax.effectSpecifiers?.asyncSpecifier != nil {
                accessors.isAsync = true
            }
            if accessorSyntax.effectSpecifiers?.throwsSpecifier != nil {
                accessors.isThrows = true
            }
            var body: CodeBlock? = nil
            if let bodySyntax = accessorSyntax.body {
                let statements = StatementDecoder.decode(syntaxListContainer: bodySyntax, in: syntaxTree)
                body = CodeBlock(statements: statements)
            }

            switch accessorSyntax.accessorSpecifier.text {
            case "get":
                accessors.getter = Accessor(body: body)
            case "set":
                let parameterName = accessorSyntax.parameter?.name.text
                accessors.setter = Accessor(parameterName: parameterName, body: body)
            case "willSet":
                let parameterName = accessorSyntax.parameter?.name.text
                accessors.willSet = Accessor(parameterName: parameterName, body: body)
            case "didSet":
                accessors.didSet = Accessor(body: body)
            default:
                accessors.messages.append(.unsupportedSyntax(self, source: syntaxTree.source))
            }
        }
        return accessors
    }
}

struct Accessors {
    var getter: Accessor<CodeBlock>?
    var setter: Accessor<CodeBlock>?
    var willSet: Accessor<CodeBlock>?
    var didSet: Accessor<CodeBlock>?
    var isAsync = false
    var isThrows = false
    var messages: [Message] = []
}

extension ClosureSignatureSyntax {
    /// The return type and parameters in this signature, and optional messages warning of any issues.
    func typeSignatures(in syntaxTree: SyntaxTree) -> (TypeSignature, [Parameter<Void>], [Message]) {
        var messages: [Message] = []
        let returnType = returnClause?.typeSignature(in: syntaxTree, messages: &messages) ?? .none
        let parameters: [Parameter<Void>]
        switch parameterClause {
        case .simpleInput(let syntax):
            parameters = syntax.map { Parameter<Void>(externalLabel: $0.name.text) }
        case .parameterClause(let syntax):
            parameters = syntax.parameters(in: syntaxTree, messages: &messages).map {
                return Parameter<Void>(externalLabel: $0.externalLabel, declaredType: $0.declaredType, isVariadic: $0.isVariadic)
            }
        case .none:
            parameters = []
        }
        return (returnType, parameters, messages)
    }
}

extension ClosureParameterClauseSyntax {
    fileprivate func parameters(in syntaxTree: SyntaxTree, messages: inout [Message]) -> [Parameter<Expression>] {
        return parameters.map { parameterSyntax in
            Parameter<Expression>(firstName: parameterSyntax.firstName.text, secondName: parameterSyntax.secondName?.text, typeSyntax: parameterSyntax.type, ellipses: parameterSyntax.ellipsis?.text, in: syntaxTree, messages: &messages)
        }
    }
}

extension EnumCaseParameterClauseSyntax {
    func parameters(in syntaxTree: SyntaxTree) -> ([Parameter<Expression>], [Message]) {
        var messages: [Message] = []
        let parameters = parameters(in: syntaxTree, messages: &messages)
        return (parameters, messages)
    }

    fileprivate func parameters(in syntaxTree: SyntaxTree, messages: inout [Message]) -> [Parameter<Expression>] {
        return parameters.map { parameterSyntax in
            Parameter<Expression>(firstName: parameterSyntax.firstName?.text, secondName: parameterSyntax.secondName?.text, typeSyntax: parameterSyntax.type, defaultArgument: parameterSyntax.defaultArgument, in: syntaxTree, messages: &messages)
        }
    }
}

extension PatternSyntax {
    /// Return the identifier names for this pattern declaration.
    ///
    /// - Returns: A single name for a simple identifier, an array of names for a decomposed tuple.
    func identifierPatterns(in syntaxTree: SyntaxTree) -> [IdentifierPattern]? {
        // TODO: Support additional patterns
        switch kind {
        case .expressionPattern:
            guard let expressionSyntax = self.as(ExpressionPatternSyntax.self) else {
                return nil
            }
            return expressionSyntax.expression.identifierPatterns(in: syntaxTree)
        case .identifierPattern:
            guard let identifierSyntax = self.as(IdentifierPatternSyntax.self) else {
                return nil
            }
            return [IdentifierPattern(name: identifierSyntax.identifier.text)]
        case .isTypePattern:
            return nil
        case .missingPattern:
            return nil
        case .tuplePattern:
            guard let tupleSyntax = self.as(TuplePatternSyntax.self) else {
                return nil
            }
            var identifierPatterns: [IdentifierPattern] = []
            for element in tupleSyntax.elements {
                guard let elementPatterns = element.pattern.identifierPatterns(in: syntaxTree) else {
                    return nil
                }
                identifierPatterns += elementPatterns
            }
            return identifierPatterns
        case .valueBindingPattern:
            guard let valueBindingSyntax = self.as(ValueBindingPatternSyntax.self) else {
                return nil
            }
            guard let identifierPatterns = valueBindingSyntax.pattern.identifierPatterns(in: syntaxTree) else {
                return nil
            }
            let isVar = valueBindingSyntax.bindingSpecifier.text == "var"
            return identifierPatterns.map { IdentifierPattern(name: $0.name, isVar: $0.isVar || isVar) }
        case .wildcardPattern:
            return [IdentifierPattern(name: nil)]
        default:
            return nil
        }
    }

    /// Extract and decode the expression from this pattern.
    ///
    /// If this pattern is a pure binding, returns `Binding`.
    func expression(in syntaxTree: SyntaxTree) -> (expression: Expression, isVar: Bool) {
        switch kind {
        case .expressionPattern:
            if let expressionSyntax = self.as(ExpressionPatternSyntax.self) {
                let expression = ExpressionDecoder.decode(syntax: expressionSyntax.expression, in: syntaxTree)
                return (expression, false)
            }
        case .valueBindingPattern:
            if let valueBindingSyntax = self.as(ValueBindingPatternSyntax.self) {
                let (expression, _) = valueBindingSyntax.pattern.expression(in: syntaxTree)
                let isVar = valueBindingSyntax.bindingSpecifier.text == "var"
                return (expression, isVar)
            }
        default:
            break
        }
        let expression = ExpressionDecoder.decode(syntax: self, in: syntaxTree)
        return (expression, false)
    }
}

extension ExprSyntaxProtocol {
    /// Return the identifier names for this pattern declaration.
    ///
    /// - Returns: A single name for a simple identifier, an array of names for a decomposed tuple.
    func identifierPatterns(in syntaxTree: SyntaxTree) -> [IdentifierPattern]? {
        switch kind {
        case .discardAssignmentExpr:
            return [IdentifierPattern(name: nil)]
        case .identifierExpr:
            guard let identifierExpr = self.as(IdentifierExprSyntax.self) else {
                return nil
            }
            return [IdentifierPattern(name: identifierExpr.identifier.text)]
        case .tupleExpr:
            guard let tupleExpr = self.as(TupleExprSyntax.self) else {
                return nil
            }
            var identifierPatterns: [IdentifierPattern] = []
            for element in tupleExpr.elements {
                guard let elementPatterns = element.expression.identifierPatterns(in: syntaxTree) else {
                    return nil
                }
                identifierPatterns += elementPatterns
            }
            return identifierPatterns
        case .unresolvedPatternExpr:
            // We've seen this pattern in e.g. 'if let (a, b) = optionalTuple'
            guard let patternExpr = self.as(UnresolvedPatternExprSyntax.self) else {
                return nil
            }
            return patternExpr.pattern.identifierPatterns(in: syntaxTree)
        default:
            return nil
        }
    }
}

extension TypeEffectSpecifiersSyntax {
    /// Return the API flags in these specifiers.
    var apiFlags: APIFlags {
        return APIFlags(isAsync: asyncSpecifier?.text != nil, isThrows: throwsSpecifier?.text != nil)
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
    var endOfListSyntax: SyntaxProtocol { get }
}

// MARK: - Conformances

extension SourceFileSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }

    var endOfListSyntax: SyntaxProtocol {
        return self.endOfFileToken
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

    var endOfListSyntax: SyntaxProtocol {
        return self.rightBrace
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

    var endOfListSyntax: SyntaxProtocol {
        return self.rightBrace
    }
}

extension ClosureExprSyntax: SyntaxListContainer {
    var syntaxList: CodeBlockItemListSyntax {
        return self.statements
    }

    var endOfListSyntax: SyntaxProtocol {
        return self.rightBrace
    }
}
