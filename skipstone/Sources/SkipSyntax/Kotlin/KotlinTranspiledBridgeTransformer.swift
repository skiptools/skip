import Foundation

/// Generate transpiled Swift (Kotlin) to compiled Swift bridging code.
final class KotlinTranspiledBridgeTransformer: KotlinTransformer {
    private var swiftDefinitions: [SwiftDefinitions] = []
    private var lock = NSLock()

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        guard !syntaxTree.isBridgeFile else {
            return
        }
        var localSwiftDefinitions: [SwiftDefinitions] = []
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? KotlinVariableDeclaration, variableDeclaration.role == .global {
                addSwiftDefinitions(for: variableDeclaration, to: &localSwiftDefinitions, translator: translator)
                return .skip
            }
            return .recurse(nil)
        }
        if !localSwiftDefinitions.isEmpty {
            lock.lock()
            swiftDefinitions += localSwiftDefinitions
            lock.unlock()
        }
    }

    func apply(toSwiftBridge syntaxTree: SyntaxTree, imports: inout Set<String>, translator: KotlinTranslator) -> Bool {
        guard !swiftDefinitions.isEmpty else {
            return false
        }

        imports.insert("SkipJNI")
        // TODO: Imports
        // TODO: Uniquify java file classes
        let swiftStatements = swiftDefinitions.map { swiftDefinitionStatements(for: $0) }
        syntaxTree.root.statements += swiftStatements
        return true
    }

    private func addSwiftDefinitions(for variableDeclaration: KotlinVariableDeclaration, to swiftDefinitions: inout [SwiftDefinitions], translator: KotlinTranslator) {

    }

    private func swiftDefinitionStatements(for swiftDefinitions: SwiftDefinitions) -> RawStatement {
        let sourceCode = swiftDefinitions.definitions.joined(separator: "\n")
        return RawStatement(sourceCode: sourceCode)
    }
}

private struct SwiftDefinitions {
    let fileClassName: String?
    let definitions: [String]
}
