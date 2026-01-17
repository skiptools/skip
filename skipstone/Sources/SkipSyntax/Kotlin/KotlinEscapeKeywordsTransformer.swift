// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Append an underscore to the end of hard keywords in Kotlin, since they cannot be otherwise escaped.
final class KotlinEscapeKeywordsTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        let visitor = EscapeKeywordsVisitor()
        syntaxTree.root.visit(perform: visitor.visit)
        return []
    }
}

/// Appends an underscore to the end of hard keywords in Kotlin.
private final class EscapeKeywordsVisitor {
    func fixKeyword(name: String) -> String {
        return name.fixingKeyword(in: KotlinIdentifier.hardKeywords)
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
            let name = node.name
            node.name = fixKeyword(name: node.name)
            if node.name != name {
                node.preEscapedName = name
            }
            let parameterLabels = node.parameters.map(\.externalLabel)
            node.parameters = node.parameters.map(fixParameter)
            node.preEscapedParameterLabels = zip(node.parameters, parameterLabels).map {
                return $0.externalLabel == $1 ? nil : $1
            }
        } else if let node = node as? KotlinFunctionCall {
            node.arguments = node.arguments.map(fixLabeledArgument)
        } else if let node = node as? KotlinVariableDeclaration {
            let propertyName = node.propertyName
            node.names = node.names.map {
                $0.map(fixKeyword)
            }
            if node.propertyName != propertyName {
                node.preEscapedPropertyName = propertyName
            }
        } else if let node = node as? KotlinEnumCaseDeclaration {
            let name = node.name
            node.name = fixKeyword(name: name)
            if node.name != name {
                node.preEscapedName = name
            }
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
