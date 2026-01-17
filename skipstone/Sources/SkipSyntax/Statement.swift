// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftSyntax

/// A statement in the Swift syntax tree.
class Statement: SyntaxNode {
    let type: StatementType
    var extras: StatementExtras?

    init(type: StatementType, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.type = type
        self.extras = extras
        super.init(nodeName: String(describing: type), syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange)
    }

    /// Attempt to construct statements of this type from the given syntax.
    ///
    /// - Throws: `Message` when unable to decode a compatible syntax.
    class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, context: DecodeContext, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        return nil
    }

    final override var subtreeMessages: [Message] {
        if extras?.suppressMessages == true {
            // Filter out our own messages and any child Expression messages, but leave child statements
            return children.filter { $0 is Statement }.flatMap { $0.subtreeMessages }
        } else {
            return messages + children.flatMap { $0.subtreeMessages }
        }
    }

    /// How to decode a declaration with the given attributes and visibility.
    static func decodeLevel(attributes: Attributes, visibility: Modifiers.Visibility, context: DecodeContext, in syntaxTree: SyntaxTree) -> DecodeLevel {
        // For full or none levels, no logic needed. Transpiled module files will always be in .full mode
        guard syntaxTree.decodeLevel != .full && syntaxTree.decodeLevel != .none else {
            return syntaxTree.decodeLevel
        }
        // Fully decode #if SKIP content and any expressions we're already decoding (e.g. local var decl inside code block)
        guard !context.isInIfSkipBlock && !context.isInExpression else {
            return .full
        }
        let effectiveVisibility: Modifiers.Visibility
        if context.memberOf?.type == .protocolDeclaration && !(self is TypeDeclaration.Type) {
            effectiveVisibility = visibility == .default || visibility >= .public ? .public : visibility
        } else if context.memberOf?.type == .extensionDeclaration {
            effectiveVisibility = visibility == .default ? (context.memberOf?.modifiers.visibility ?? visibility) : visibility
        } else if self is ExtensionDeclaration.Type {
            // Extensions with default visibility may contain public members
            effectiveVisibility = visibility == .default || visibility >= .public ? .public : visibility
        } else {
            effectiveVisibility = visibility
        }
        let bridgeMemberVisibility: Modifiers.Visibility?
        if let memberOf = context.memberOf, memberOf.flags.contains(.bridgeMembers) {
            bridgeMemberVisibility = memberOf.modifiers.visibility
        } else {
            bridgeMemberVisibility = nil
        }
        return isBridging(attributes: attributes, visibility: effectiveVisibility, bridgeMemberVisibility: bridgeMemberVisibility, autoBridge: syntaxTree.autoBridge) ? .api : .none
    }
}

/// A general statement hosting an `Expression`.
///
/// - Seealso: ``Expression``
class ExpressionStatement: Statement {
    let expression: Expression?

    init(type: StatementType = .expression, expression: Expression? = nil, syntax: SyntaxProtocol? = nil, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil, extras: StatementExtras? = nil) {
        self.expression = expression
        super.init(type: type, syntax: syntax, sourceFile: sourceFile, sourceRange: sourceRange, extras: extras)
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, context: DecodeContext, in syntaxTree: SyntaxTree) throws -> [Statement]? {
        if syntax.kind == .expressionStmt, let expressionStmnt = syntax.as(ExpressionStmtSyntax.self) {
            let expression = ExpressionDecoder.decode(syntax: expressionStmnt.expression, in: syntaxTree)
            return [ExpressionStatement(expression: expression, syntax: expressionStmnt.expression, sourceFile: syntaxTree.source.file, sourceRange: expressionStmnt.expression.range(in: syntaxTree.source), extras: extras)]
        } else if let expression = ExpressionDecoder.decodeIfExpression(syntax: syntax, in: syntaxTree) {
            return [ExpressionStatement(expression: expression, syntax: syntax, sourceFile: syntaxTree.source.file, sourceRange: syntax.range(in: syntaxTree.source), extras: extras)]
        } else {
            return nil
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        return expression?.inferTypes(context: context, expecting: expecting) ?? context
    }

    override var inferredType: TypeSignature {
        return expression?.inferredType ?? .none
    }

    override var children: [SyntaxNode] {
        return expression == nil ? [] : [expression!]
    }
}

/// Attach a warning or error to the tree.
final class MessageStatement: Statement {
    init(message: Message) {
        super.init(type: .message)
        self.messages = [message]
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, context: DecodeContext, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }
}

/// Raw source code.
final class RawStatement: Statement {
    let sourceCode: String

    init(sourceCode: String, message: Message? = nil, syntax: SyntaxProtocol? = nil, range: Source.Range? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree? = nil) {
        self.sourceCode = sourceCode
        var range = range
        if range == nil, let source = syntaxTree?.source {
            range = syntax?.range(in: source)
        }
        super.init(type: .raw, syntax: syntax, sourceFile: syntaxTree?.source.file, sourceRange: range, extras: extras)
        if let message {
            self.messages = [message]
        }
    }

    init(syntax: SyntaxProtocol, message: Message? = nil, extras: StatementExtras? = nil, in syntaxTree: SyntaxTree) {
        self.sourceCode = syntax.description
        let source = syntaxTree.source
        let range = syntax.range(in: source)
        super.init(type: .raw, syntax: syntax, sourceFile: source.file, sourceRange: range, extras: extras)
        if let message {
            self.messages = [message]
        } else {
            self.messages = [.unsupportedSyntax(syntax, source: source)]
        }
    }

    override func inferTypes(context: TypeInferenceContext, expecting: TypeSignature) -> TypeInferenceContext {
        expectedType = expecting
        return context
    }

    private var expectedType: TypeSignature = .none

    override var inferredType: TypeSignature {
        return expectedType
    }

    override class func decode(syntax: SyntaxProtocol, extras: StatementExtras?, context: DecodeContext, in syntaxTree: SyntaxTree) -> [Statement]? {
        return nil
    }

    override var prettyPrintAttributes: [PrettyPrintTree] {
        return [PrettyPrintTree(root: sourceCode)]
    }
}
