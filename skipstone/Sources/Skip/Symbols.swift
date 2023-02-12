import Foundation
import SymbolKit

/// Provides information about code symbols.
///
/// Currently an abstraction over `SymbolKit`.
///
/// The build artifacts required to extract symbol information are not always present for build plugins or command line tools, so all symbol
/// info is optional for operations other than final transpilation.
public class Symbols {
    /// The current module name.
    public let moduleName: String

    private var symbolsByIdentifier: [String: Symbol] = [:]
    private var symbolsByName: [String: [Symbol]] = [:]

    public init(moduleName: String, graphs: [String: UnifiedSymbolGraph]) {
        self.moduleName = moduleName
        for entry in graphs {
            processGraph(entry.value, moduleName: entry.key)
        }
    }

    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.File? = nil) -> Context {
        return Context(symbols: self, importedModuleNames: Set(importedModuleNames), sourceFile: sourceFile)
    }

    /// A context for accessing symbol information.
    struct Context {
        private let symbols: Symbols
        private let importedModuleNames: Set<String>
        private let sourceFile: Source.File?

        fileprivate init(symbols: Symbols, importedModuleNames: Set<String>, sourceFile: Source.File?) {
            self.symbols = symbols
            self.importedModuleNames = importedModuleNames
            self.sourceFile = sourceFile
        }

        /// Return the type of the given member.
        func type(of member: String, in type: TypeSignature) -> TypeSignature {
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if member == label || member == "\(index)" {
                        return types[index]
                    }
                }
                return .none
            }

            let typeNames = candidateTypeNames(for: type)
            for typeName in typeNames {
                let type = self.type(of: member, in: typeName)
                if type != .none {
                    return type
                }
            }
            return .none
        }

        private func type(of member: String, in typeName: String) -> TypeSignature {
            return .none //~~~
        }

        /// Return the type of the given identifier.
        func type(of identifier: String) -> TypeSignature {
            return .none
        }

        /// Return the signatures of the possible member functions being called with the given arguments.
        func functionSignature(of name: String, in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            return []
        }

        /// Return the signatures of the possible functions being called with the given arguments.
        func functionSignature(of name: String, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            return []
        }

        /// Return the signatures of the possible subscripts being called with the given arguments.
        func subscriptSignature(in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            return []
        }

        private func candidateTypeNames(for type: TypeSignature) -> [String] {
            switch type {
            case .array:
                return ["Array"]
            case .composition(let types):
                return types.flatMap { candidateTypeNames(for: $0) }
            case .dictionary:
                return ["Dictionary"]
            case .function:
                return []
            case .member:
                return []
            case .named(let name, _):
                return [name]
            case .none:
                return []
            case .optional(let type):
                return candidateTypeNames(for: type)
            case .set:
                return ["Set"]
            case .unwrappedOptional(let type):
                return candidateTypeNames(for: type)
            case .void:
                return []
            default:
                return [type.description]
            }
        }
    }

    private func processGraph(_ graph: UnifiedSymbolGraph, moduleName: String) {
        for entry in graph.symbols {
            if let symbol = symbol(for: entry.value, moduleName: moduleName) {
                symbolsByIdentifier[symbol.symbol.uniqueIdentifier] = symbol
            }
        }
        if let relationships = graph.relationshipsByLanguage.first(where: { $0.key.interfaceLanguage == "swift" })?.value {
            for relationship in relationships {
                processRelationship(relationship)
            }
        }
        for symbol in symbolsByIdentifier.values {
            var symbolsWithName = symbolsByName[symbol.name] ?? []
            symbolsWithName.append(symbol)
            symbolsByName[symbol.name] = symbolsWithName
        }
    }

    private func symbol(for symbol: UnifiedSymbolGraph.Symbol, moduleName: String) -> Symbol? {
        guard let symbol = Symbol(symbol: symbol, moduleName: moduleName) else {
            return nil
        }
        // No need to record symbols for non-public API of another module
        guard moduleName != self.moduleName || symbol.visibility == .public || symbol.visibility == .open else {
            return nil
        }
        return symbol
    }

    private func processRelationship(_ relationship: SymbolGraph.Relationship) {
        guard var source = symbolsByIdentifier[relationship.source], var target = symbolsByIdentifier[relationship.target] else {
            return
        }
        source.relationships.append(Symbol.Relationship(kind: relationship.kind, targetIdentifier: target.symbol.uniqueIdentifier, isInverse: false))
        target.relationships.append(Symbol.Relationship(kind: relationship.kind, targetIdentifier: source.symbol.uniqueIdentifier, isInverse: true))
        symbolsByIdentifier[source.symbol.uniqueIdentifier] = source
        symbolsByIdentifier[target.symbol.uniqueIdentifier] = target
    }
}

private struct Symbol {
    let symbol: UnifiedSymbolGraph.Symbol
    let name: String
    let moduleName: String
    let sourceURL: URL?
    var relationships: [Relationship] = []

    private let selector: UnifiedSymbolGraph.Selector
    private let mixins: [String: Mixin]
    private let declarationFragments: SymbolGraph.Symbol.DeclarationFragments

    init?(symbol: UnifiedSymbolGraph.Symbol, moduleName: String) {
        guard let selector = symbol.names.keys.first(where: { $0.interfaceLanguage == "swift" }) else {
            return nil
        }
        guard let mixins = symbol.mixins[selector] else {
            return nil
        }
        guard let declarationFragments = mixins[SymbolGraph.Symbol.DeclarationFragments.mixinKey] as? SymbolGraph.Symbol.DeclarationFragments else {
            return nil
        }
        guard let name = declarationFragments.declarationFragments.first(where: { $0.kind == .identifier })?.spelling else {
            return nil
        }

        self.selector = selector
        self.symbol = symbol
        self.name = name
        self.moduleName = moduleName
        self.sourceURL = (mixins[SymbolGraph.Symbol.Location.mixinKey] as? SymbolGraph.Symbol.Location)?.url
        self.mixins = mixins
        self.declarationFragments = declarationFragments
    }

    var kind: SymbolGraph.Symbol.KindIdentifier? {
        return symbol.kind[selector]?.identifier
    }

    var visibility: Visibility {
        guard let rawValue = symbol.accessLevel[selector]?.rawValue else {
            return .internal
        }
        return Visibility(rawValue: rawValue) ?? .internal
    }

    var isVariableReadOnly: Bool {
        return declarationFragments.hasKeyword("let") || (declarationFragments.hasKeyword("get") && !declarationFragments.hasKeyword("set"))
    }

    var variableType: SymbolGraph.Symbol.DeclarationFragments.Fragment? {
        return declarationFragments.declarationFragments.first { $0.kind == .typeIdentifier }
    }

    var returnType: SymbolGraph.Symbol.DeclarationFragments.Fragment? {
        guard let functionSignature = mixins[SymbolGraph.Symbol.FunctionSignature.mixinKey] as? SymbolGraph.Symbol.FunctionSignature else {
            return nil
        }
        return functionSignature.returns.first { $0.kind == .typeIdentifier }
    }

    var parameterTypes: [(String, SymbolGraph.Symbol.DeclarationFragments.Fragment?)] {
        guard let functionSignature = mixins[SymbolGraph.Symbol.FunctionSignature.mixinKey] as? SymbolGraph.Symbol.FunctionSignature else {
            return []
        }
        return functionSignature.parameters.map { parameter in
            let name = parameter.name
            let typeFragment = parameter.declarationFragments.first { $0.kind == .typeIdentifier }
            return (name, typeFragment)
        }
    }

    enum Visibility: String, RawRepresentable {
        case `public`
        case `open`
        case `internal`
        case `private`
    }

    struct Relationship {
        let kind: SymbolGraph.Relationship.Kind
        let targetIdentifier: String
        let isInverse: Bool
    }
}

private extension SymbolGraph.Symbol.DeclarationFragments {
    func hasKeyword(_ keyword: String) -> Bool {
        return declarationFragments.contains { $0.kind == .keyword && $0.spelling == keyword }
    }
}
