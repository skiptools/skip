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

    fileprivate var symbolsByIdentifier: [String: Symbol] = [:]
    fileprivate var symbolsByName: [String: [Symbol]] = [:]

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

    /// Whether the given name maps to a symbol that is known to be a mutable value type.
    ///
    /// - Returns: true if a symbol exists for a mutable value type, false if only immutable type symbols exist, and nil if no type symbol exists.
    func containsMutableValueType(name: String) -> Bool? {
        guard let candidates = symbolsByName[name] else {
            return nil
        }
        var hasType = false
        for candidate in candidates {
            guard let kind = candidate.kind else {
                continue
            }
            switch kind {
            case .class:
                hasType = true
            case .enum:
                hasType = true
            case .struct:
                if isMutableStruct(candidate) {
                    return true
                }
                hasType = true
            case .protocol:
                if !isAnyObjectRestrictedProtocol(candidate) {
                    return true
                }
                hasType = true
            default:
                break
            }
        }
        return hasType ? false : nil
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

        /// Return the type of the given identifier.
        func type(of identifier: String) -> TypeSignature {
            let candidates = symbols.symbolsByName[identifier, default: []].filter { $0.kind == .var }
            return ranked(candidates).first?.typeSignature(symbols: symbols) ?? .none
        }

        /// Return the signatures of the possible member functions being called with the given arguments.
        func functionSignature(of name: String, in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            if case .tuple(let labels, let types) = type {
                for (index, label) in labels.enumerated() {
                    if name == label || name == "\(index)" {
                        let function = matchFunction(types[index], arguments: arguments)
                        return function == .none ? [] : [function]
                    }
                }
                return []
            }

            let typeNames = candidateTypeNames(for: type)
            for typeName in typeNames {
                let functions = self.functionSignature(of: name, in: typeName, arguments: arguments)
                if !functions.isEmpty {
                    return functions
                }
            }
            return []
        }

        /// Return the signatures of the possible functions being called with the given arguments.
        func functionSignature(of name: String, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            let candidates = symbols.symbolsByName[name, default: []]
                .filter { $0.kind == .func }
                .compactMap { matchFunction($0, arguments: arguments) }
            return ranked(candidates).map(\.signature)
        }

        /// Return the signatures of the possible subscripts being called with the given arguments.
        func subscriptSignature(in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            let typeNames = candidateTypeNames(for: type)
            for typeName in typeNames {
                let functions = self.functionSignature(of: "subscript", in: typeName, arguments: arguments)
                if !functions.isEmpty {
                    return functions
                }
            }
            return []
        }

        private func type(of member: String, in typeName: String) -> TypeSignature {
            let candidates = ranked(symbols.symbolsByName[typeName] ?? [])
            for candidate in candidates {
                let type = type(of: member, in: candidate)
                if type != .none {
                    return type
                }
            }
            return .none
        }

        private func type(of member: String, in candidate: Symbol) -> TypeSignature {
            for relationship in candidate.relationships {
                switch relationship.kind {
                case .memberOf:
                    guard relationship.isInverse, let member = symbols.symbolsByIdentifier[relationship.targetIdentifier ?? ""] else {
                        break
                    }
                    return member.typeSignature(symbols: symbols)
                case .inheritsFrom:
                    guard !relationship.isInverse, let inheritsFrom = symbols.symbolsByIdentifier[relationship.targetIdentifier ?? ""] else {
                        break
                    }
                    let type = type(of: member, in: inheritsFrom)
                    if type != .none {
                        return type
                    }
                default:
                    break
                }
            }
            return .none
        }

        private func functionSignature(of name: String, in typeName: String, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            let candidates = ranked(symbols.symbolsByName[typeName] ?? [])
            var functions: [(symbol: Symbol, signature: TypeSignature)] = []
            for candidate in candidates {
                for function in functionSignature(of: name, in: candidate, arguments: arguments) {
                    if !functions.contains(where: { $0.signature == function.signature }) {
                        functions.append(function)
                    }
                }
            }
            return ranked(functions).map(\.signature)
        }

        private func functionSignature(of name: String, in candidate: Symbol, arguments: [LabeledValue<TypeSignature>]) -> [(symbol: Symbol, signature: TypeSignature)] {
            var functions: [(symbol: Symbol, signature: TypeSignature)] = []
            for relationship in candidate.relationships {
                switch relationship.kind {
                case .memberOf:
                    guard relationship.isInverse, let member = symbols.symbolsByIdentifier[relationship.targetIdentifier ?? ""] else {
                        break
                    }
                    if let function = matchFunction(member, arguments: arguments) {
                        functions.append(function)
                    }
                case .inheritsFrom:
                    guard !relationship.isInverse, let inheritsFrom = symbols.symbolsByIdentifier[relationship.targetIdentifier ?? ""] else {
                        break
                    }
                    functions += functionSignature(of: name, in: inheritsFrom, arguments: arguments)
                default:
                    break
                }
            }
            return functions
        }

        private func matchFunction(_ symbol: Symbol, arguments: [LabeledValue<TypeSignature>]) -> (symbol: Symbol, signature: TypeSignature)? {
            let parameters = symbol.parameters
            guard parameters.count >= arguments.count else {
                return nil
            }

            // Match each argument to a parameter
            var matchingParameterTypes: [TypeSignature] = []
            var parameterIndex = 0
            for argument in arguments {
                guard let matchingIndex = matchArgument(argument, to: parameters, startIndex: parameterIndex) else {
                    return nil
                }
                matchingParameterTypes.append(parameters[matchingIndex].type?.typeSignature(symbols: symbols).or(argument.value) ?? argument.value)
                parameterIndex = matchingIndex + 1
            }
            // Make sure there are no more required parameters
            if parameterIndex < parameters.count {
                if parameters[parameterIndex...].contains(where: { !$0.hasDefaultValue }) {
                    return nil
                }
            }

            let returnType = symbol.returnType?.typeSignature(symbols: symbols) ?? .none
            return (symbol, .function(matchingParameterTypes, returnType))
        }

        private func matchFunction(_ signature: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> TypeSignature {
            guard case .function(let parameterTypes, _) = signature, parameterTypes.count == arguments.count else {
                return .none
            }
            return signature
        }

        private func matchArgument(_ argument: LabeledValue<TypeSignature>, to parameters: [Symbol.Parameter], startIndex: Int) -> Int? {
            for (index, parameter) in parameters[startIndex...].enumerated() {
                if let label = argument.label {
                    // If there is a label, then it either has to match or we have to be able to skip this parameter
                    if parameter.label == label {
                        return startIndex + index
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                } else {
                    // If there is no label, then either this parameter has to have no label or it has to be a trailing closure
                    if parameter.label == "_" {
                        return startIndex + index
                    } else if let type = parameter.type, case .function = type.typeSignature(symbols: symbols) {
                        return startIndex + index
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                }
            }
            return nil
        }

        private func ranked(_ symbols: [Symbol]) -> [Symbol] {
            return zip(symbols, symbols.map { rankScore(of: $0) })
                .filter { $0.1 > 0 } // score > 0
                .sorted { $0.1 < $1.1 } // sort on score
                .map(\.0) // return symbol
        }

        private func ranked(_ functions: [(symbol: Symbol, signature: TypeSignature)]) -> [(symbol: Symbol, signature: TypeSignature)] {
            return zip(functions, functions.map { rankScore(of: $0.symbol) })
                .filter { $0.1 > 0 }  // score > 0
                .sorted { $0.1 < $1.1 } // sort on score
                .map(\.0) // return function
        }

        private func rankScore(of symbol: Symbol) -> Int {
            var score = 0
            if symbol.moduleName == symbols.moduleName {
                // Favor a symbol in this module
                score += 2
                // Favor a symbol in this file
                if let symbolURL = symbol.sourceURL, let sourcePath = sourceFile?.path, symbolURL.path.hasSuffix(sourcePath) {
                    score += 1
                }
            } else if importedModuleNames.contains(symbol.moduleName) {
                score += 1
            }
            return score
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

    private func isMutableStruct(_ symbol: Symbol) -> Bool {
        for relationship in symbol.relationships {
            guard relationship.kind == .memberOf && relationship.isInverse else {
                continue
            }
            guard let member = symbolsByIdentifier[relationship.targetIdentifier ?? ""], let memberKind = member.kind else {
                // Assume any unknown member might be mutating
                return true
            }
            switch memberKind {
            case .property:
                if member.isVariableReadWrite {
                    return true
                }
            case .method:
                if member.isFunctionMutating {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private func isAnyObjectRestrictedProtocol(_ symbol: Symbol) -> Bool {
        if symbol.isAnyObjectRestricted {
            return true
        }
        for relationship in symbol.relationships {
            guard relationship.kind == .conformsTo, !relationship.isInverse, let conformsTo = symbolsByIdentifier[relationship.targetIdentifier ?? ""] else {
                continue
            }
            if isAnyObjectRestrictedProtocol(conformsTo) {
                return true
            }
        }
        return false
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
        guard moduleName == self.moduleName || symbol.visibility == .public || symbol.visibility == .open else {
            return nil
        }
        return symbol
    }

    private func processRelationship(_ relationship: SymbolGraph.Relationship) {
        guard var source = symbolsByIdentifier[relationship.source] else {
            return
        }
        guard var target = symbolsByIdentifier[relationship.target] else {
            if let fallback = relationship.targetFallback, fallback.hasPrefix("Swift.") {
                source.relationships.append(Symbol.Relationship(kind: relationship.kind, targetIdentifier: nil, targetSwiftType: String(fallback.dropFirst("Swift.".count)), isInverse: false))
                symbolsByIdentifier[source.symbol.uniqueIdentifier] = source
            }
            return
        }
        source.relationships.append(Symbol.Relationship(kind: relationship.kind, targetIdentifier: target.symbol.uniqueIdentifier, targetSwiftType: nil, isInverse: false))
        target.relationships.append(Symbol.Relationship(kind: relationship.kind, targetIdentifier: source.symbol.uniqueIdentifier, targetSwiftType: nil, isInverse: true))
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

    func typeSignature(symbols: Symbols) -> TypeSignature {
        guard let kind else {
            return .none
        }
        switch kind {
        case .case:
            guard let memberOf = relationships.first(where: { $0.kind == .memberOf && !$0.isInverse }), let e = symbols.symbolsByIdentifier[memberOf.targetIdentifier ?? ""] else {
                return .none
            }
            return e.typeSignature(symbols: symbols)
        case .class:
            return .named(name, [])
        case .enum:
            return .named(name, [])
        case .extension:
            guard let extensionTo = relationships.first(where: { $0.kind == .extensionTo && !$0.isInverse }) else {
                return .none
            }
            guard let t = symbols.symbolsByIdentifier[extensionTo.targetIdentifier ?? ""] else {
                if let swiftTypeName = extensionTo.targetSwiftType {
                    return TypeSignature.for(name: swiftTypeName, genericTypes: [])
                } else {
                    return .none
                }
            }
            return t.typeSignature(symbols: symbols)
        case .method:
            fallthrough
        case .func:
            let rt = returnType?.typeSignature(symbols: symbols) ?? .none
            let pts = parameters.map { $0.type?.typeSignature(symbols: symbols) ?? .none }
            return .function(pts, rt)
        case .property:
            fallthrough
        case .var:
            return variableType?.typeSignature(symbols: symbols) ?? .none
        case .protocol:
            return .named(name, [])
        case .struct:
            // Could be array, dictionary so pass through TypeSignature
            return TypeSignature.for(name: name, genericTypes: [])
        default:
            return .none
        }
    }

    var isAnyObjectRestricted: Bool {
        // We get a fragment like ': AnyObject'
        for fragment in declarationFragments.declarationFragments {
            guard fragment.spelling.contains(":") else {
                continue
            }
            return fragment.spelling.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ":" }).contains("AnyObject")
        }
        return false
    }

    var isVariableReadWrite: Bool {
        return !declarationFragments.hasKeyword("let") && (!declarationFragments.hasKeyword("get") || declarationFragments.hasKeyword("set"))
    }

    var isFunctionMutating: Bool {
        return declarationFragments.hasKeyword("mutating")
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

    var parameters: [Parameter] {
        guard let functionSignature = mixins[SymbolGraph.Symbol.FunctionSignature.mixinKey] as? SymbolGraph.Symbol.FunctionSignature else {
            return []
        }
        return functionSignature.parameters.map { parameter in
            let name = parameter.name
            let hasDefaultValue = parameter.declarationFragments.contains { $0.spelling == "=" }
            let typeFragment = parameter.declarationFragments.first { $0.kind == .typeIdentifier }
            return Parameter(label: name, hasDefaultValue: hasDefaultValue, type: typeFragment)
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
        let targetIdentifier: String?
        let targetSwiftType: String?
        let isInverse: Bool
    }

    struct Parameter {
        let label: String
        let hasDefaultValue: Bool
        let type: SymbolGraph.Symbol.DeclarationFragments.Fragment?
    }
}

private extension SymbolGraph.Symbol.DeclarationFragments {
    func hasKeyword(_ keyword: String) -> Bool {
        return declarationFragments.contains { $0.kind == .keyword && $0.spelling == keyword }
    }
}

private extension SymbolGraph.Symbol.DeclarationFragments.Fragment {
    func typeSignature(symbols: Symbols) -> TypeSignature {
        if let identifier = preciseIdentifier, let symbol = symbols.symbolsByIdentifier[identifier] {
            return symbol.typeSignature(symbols: symbols)
        }
        return TypeSignature.for(name: spelling, genericTypes: [])
    }
}
