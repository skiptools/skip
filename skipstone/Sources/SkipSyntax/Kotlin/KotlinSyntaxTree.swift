/// Representation of the Kotlin syntax tree.
public final class KotlinSyntaxTree {
    let source: Source
    let bridgeAPI: BridgeAPI
    let root: KotlinCodeBlock
    var dependencies: KotlinDependencies

    init(source: Source, bridgeAPI: BridgeAPI = .none, root: KotlinCodeBlock, dependencies: KotlinDependencies = KotlinDependencies()) {
        self.source = source
        self.bridgeAPI = bridgeAPI
        self.root = root
        self.dependencies = dependencies
    }

    public var messages: [Message] {
        guard !root.statements.contains(where: { $0.extras?.isSymbolFile == true }) else {
            return []
        }
        return root.subtreeMessages
    }
}
