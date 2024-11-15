import Foundation

/// Generate bridging code and transformations.
public final class KotlinBridgeTransformer: KotlinTransformer {
    public init() {
    }

    public func gather(from syntaxTree: SyntaxTree) {
        // Add attributes marking bridged types so that they're recorded in our codebase info
        syntaxTree.root.visit { node in
            if let typeDeclaration = node as? TypeDeclaration {
                switch typeDeclaration.type {
                case .classDeclaration, .protocolDeclaration, .structDeclaration:
                    if typeDeclaration.modifiers.visibility >= .public, !typeDeclaration.attributes.isBridgeIgnored {
                        if syntaxTree.isBridgeFile {
                            typeDeclaration.attributes.attributes.append(.bridgeToKotlin)
                        } else {
                            typeDeclaration.attributes.attributes.append(.bridgeToSwift)
                        }
                    }
                default:
                    break // Unsupported
                }
                return .recurse(nil)
            } else if node is VariableDeclaration || node is FunctionDeclaration {
                return .skip
            } else {
                return .recurse(nil)
            }
        }
    }

    public func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        if syntaxTree.isBridgeFile {
            guard let visitor = KotlinBridgeToKotlinVisitor(for: syntaxTree, translator: translator) else {
                return []
            }
            return visitor.visit()
        } else {
            guard let visitor = KotlinBridgeToSwiftVisitor(for: syntaxTree, translator: translator) else {
                return []
            }
            return visitor.visit()
        }
    }
}
