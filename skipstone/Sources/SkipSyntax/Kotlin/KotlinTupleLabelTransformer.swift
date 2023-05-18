/// Determine tuple labels used within the module and generate extension properites to support them.
///
/// This transformer also generates errors for label conflicts, i.e. the same label being used to access different elements of the same N-tuple.
final class KotlinTupleLabelTransformer: KotlinTransformer {
    // Tuple arity -> Element -> Labels
    private var tupleLabels: [Int: [Int: Set<String>]] = [:]
    private var sourceFile: Source.FilePath? = nil
    private var messages: [Message] = []

    func messages(for sourceFile: Source.FilePath) -> [Message] {
        return sourceFile == self.sourceFile ? messages : []
    }

    func gather(from syntaxTree: SyntaxTree) {
        syntaxTree.root.visit { node in
            // Gather labels from tuples that we declare in our API or that we see being accessed in code
            if let variableDeclaration = node as? VariableDeclaration {
                variableDeclaration.variableTypes.forEach { gatherTupleLabels(from: $0) }
            } else if let functionDeclaration = node as? FunctionDeclaration {
                gatherTupleLabels(from: functionDeclaration.functionType)
            } else if let memberAccess = node as? MemberAccess {
                if case .tuple(let labels, _) = memberAccess.baseType, let element = labels.firstIndex(of: memberAccess.member) {
                    gatherTupleLabel(memberAccess.member, forElement: element, ofArity: labels.count)
                }
            }
            return .recurse(nil)
        }
    }

    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) {
    }

    func apply(toPackage syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> Bool {
        guard !tupleLabels.isEmpty else {
            return false
        }
        sourceFile = syntaxTree.sourceFile

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
            duplicateLabels.forEach { messages.append(.kotlinTupleConflictingLabel(label: $0, arity: tupleArity, sourceFile: syntaxTree.sourceFile)) }
        }
        return true
    }

    private func gatherTupleLabels(from type: TypeSignature) {
        // Find tuples anywhere in the type signature
        type.visit {
            if case .tuple(let labels, _) = $0 {
                for (index, label) in labels.enumerated() {
                    label.map { gatherTupleLabel($0, forElement: index, ofArity: labels.count) }
                }
            }
            return .recurse(nil)
        }
    }

    private func gatherTupleLabel(_ label: String, forElement element: Int, ofArity arity: Int) {
        var elements = tupleLabels[arity, default: [Int: Set<String>]()]
        var labels = elements[element, default: Set<String>()]
        labels.insert(label)
        elements[element] = labels
        tupleLabels[arity] = elements
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
