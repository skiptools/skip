import Foundation

/// Determine tuple labels used within the module and generate extension properites to support them.
///
/// This transformer also generates errors for label conflicts, i.e. the same label being used to access different elements of the same N-tuple.
final class KotlinTupleLabelTransformer: KotlinTransformer {
    /// Used in testing.
    static var gatherLabelsFromTypeSignatures = true

    // Tuple arity -> Element -> Labels
    private typealias TupleLabels = [Int: [Int: Set<String>]]

    private var tupleLabels: TupleLabels = [:]
    private var tupleLabelsLock = NSLock()
    private var packageSourceFile: Source.FilePath? = nil
    private var packageMessages: [Message] = []

    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return sourceFile == packageSourceFile ? packageMessages : []
    }

    func gather(from syntaxTree: SyntaxTree) {
        guard Self.gatherLabelsFromTypeSignatures else {
            return
        }
        syntaxTree.root.visit { node in
            if let variableDeclaration = node as? VariableDeclaration {
                variableDeclaration.variableTypes.forEach { gatherTupleLabels(from: $0, into: &tupleLabels) }
            } else if let functionDeclaration = node as? FunctionDeclaration {
                gatherTupleLabels(from: functionDeclaration.functionType, into: &tupleLabels)
            }
            return .recurse(nil)
        }
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
        // This function is invoked concurrently on different syntax trees, so gather labels locally and then merge
        var localLabels: TupleLabels = [:]
        syntaxTree.root.visit { node in
            // Now that we have type information, gather labels from tuples that we see being accessed in code
            if let memberAccess = node as? KotlinMemberAccess {
                if case .tuple(let labels, _) = memberAccess.baseType, let element = labels.firstIndex(of: memberAccess.member) {
                    gatherTupleLabel(memberAccess.member, forElement: element, ofArity: labels.count, into: &localLabels)
                }
            } else if let keyPath = node as? KotlinKeyPathLiteral {
                var baseType = keyPath.root
                for component in keyPath.components {
                    switch component {
                    case .property(let name, let type):
                        if case .tuple(let labels, _) = baseType, let element = labels.firstIndex(of: name) {
                            gatherTupleLabel(name, forElement: element, ofArity: labels.count, into: &localLabels)
                            baseType = type
                        }
                    default:
                        break
                    }
                }
            }
            return .recurse(nil)
        }
        if !localLabels.isEmpty {
            tupleLabelsLock.withLock {
                mergeTupleLabels(localLabels, into: &tupleLabels)
            }
        }
    }

    func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> Bool {
        // No need to lock here because this function is not invoked concurrently with any other
        guard !tupleLabels.isEmpty else {
            return false
        }
        packageSourceFile = syntaxTree.source.file

        for tupleArity in 0..<KotlinTupleLiteral.maximumArity {
            guard let elementLabels = tupleLabels[tupleArity] else {
                continue
            }
            var usedLabels: Set<String> = []
            var duplicateLabels: Set<String> = []
            for tupleElement in 0..<tupleArity {
                guard let labels = elementLabels[tupleElement] else {
                    continue
                }
                duplicateLabels.formUnion(usedLabels.intersection(labels))
                usedLabels.formUnion(labels)
                labels.sorted().forEach { addLabel($0, forElement: tupleElement, ofArity: tupleArity, in: syntaxTree) }
            }
            duplicateLabels.forEach { packageMessages.append(.kotlinTupleConflictingLabel(label: $0, arity: tupleArity, sourceFile: syntaxTree.source.file)) }
        }
        return true
    }

    private func gatherTupleLabels(from type: TypeSignature, into tupleLabels: inout TupleLabels) {
        // Find tuples anywhere in the type signature
        type.visit {
            if case .tuple(let labels, _) = $0 {
                for (index, label) in labels.enumerated() {
                    label.map { gatherTupleLabel($0, forElement: index, ofArity: labels.count, into: &tupleLabels) }
                }
            }
            return .recurse(nil)
        }
    }

    private func gatherTupleLabel(_ label: String, forElement element: Int, ofArity arity: Int, into tupleLabels: inout TupleLabels) {
        var elements = tupleLabels[arity, default: [Int: Set<String>]()]
        var labels = elements[element, default: Set<String>()]
        labels.insert(label)
        elements[element] = labels
        tupleLabels[arity] = elements
    }

    private func mergeTupleLabels(_ localLabels: TupleLabels, into tupleLabels: inout TupleLabels) {
        for arityEntry in localLabels {
            let arity = arityEntry.key
            for elementEntry in arityEntry.value {
                let element = elementEntry.key
                for label in elementEntry.value {
                    gatherTupleLabel(label, forElement: element, ofArity: arity, into: &tupleLabels)
                }
            }
        }
    }

    private func addLabel(_ label: String, forElement element: Int, ofArity arity: Int, in syntaxTree: KotlinSyntaxTree) {
        let generics = (0..<arity).map { "E\($0)" }.joined(separator: ", ")
        let declaration = "internal val <\(generics)> Tuple\(arity)<\(generics)>.\(label): E\(element)"
        let get = "    get() = element\(element)"
        let statements = [declaration, get].map { KotlinRawStatement(sourceCode: $0) }
        statements[0].extras = .singleNewline
        syntaxTree.root.insert(statements: statements, after: syntaxTree.root.statements.last)
    }
}
