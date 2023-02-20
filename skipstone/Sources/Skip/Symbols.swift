import Foundation
import SymbolKit

/// Provides information about code symbols using`SymbolKit`.
///
/// - Note: The build artifacts required to extract symbol information are not always present for build plugins or command line tools, so all symbol
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
        for symbol in symbolsByIdentifier.values {
            var symbolsWithName = symbolsByName[symbol.name] ?? []
            symbolsWithName.append(symbol)
            symbolsByName[symbol.name] = symbolsWithName
        }
    }

    /// Create a context that can access the given imported modules.
    func context(importedModuleNames: [String] = [], sourceFile: Source.File? = nil) -> Context {
        return Context(symbols: self, importedModuleNames: Set(importedModuleNames), sourceFile: sourceFile)
    }

    /// A context for accessing symbol information.
    struct Context {
        let symbols: Symbols
        private let importedModuleNames: Set<String>
        private let sourceFile: Source.File?

        fileprivate init(symbols: Symbols, importedModuleNames: Set<String>, sourceFile: Source.File?) {
            self.symbols = symbols
            var importedModuleNames = importedModuleNames
            importedModuleNames.insert("SkipKotlin") // Contains our supported subset of the Swift builtin module
            self.importedModuleNames = importedModuleNames
            self.sourceFile = sourceFile
        }

        /// The symbol for the given unique identifier.
        func lookup(identifier: String) -> Symbol? {
            return symbols.symbolsByIdentifier[identifier]
        }

        /// The symbols for the given name.
        ///
        /// - Warning: This function does not take symbol visibility into account. See `ranked`.
        func lookup(name: String) -> [Symbol] {
            return symbols.symbolsByName[name, default: []]
        }

        /// Score, sort, and filter the given symbols.
        ///
        /// - Returns: The symbols with a score > 0 in order from highest to lowest score.
        func ranked(_ symbols: [Symbol]) -> [Symbol] {
            return zip(symbols, symbols.map { rankScore(of: $0) })
                .filter { $0.1 > 0 } // score > 0
                .sorted { $0.1 > $1.1 } // sort on score
                .map(\.0) // return symbol
        }

        /// Score, sort, and filter the given object based on their symbols.
        func ranked<T>(_ objects: [T], keyPath: KeyPath<T, Symbol>) -> [T] {
            return zip(objects, objects.map { rankScore(of: $0[keyPath: keyPath]) })
                .filter { $0.1 > 0 } // score > 0
                .sorted { $0.1 > $1.1 } // sort on score
                .map(\.0) // return object
        }

        /// Score a symbol based on its visibility in this context.
        ///
        /// A score of 0 indicates that the symbol is not visible.
        func rankScore(of symbol: Symbol) -> Int {
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

        /// Return the type of the given identifier.
        func type(of identifier: String) -> TypeSignature {
            let candidates = lookup(name: identifier).filter { $0.kind == .var }
            return ranked(candidates).first?.typeSignature(symbols: symbols) ?? .none
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
            let symbolsWithName = lookup(name: name)
            let funcs = symbolsWithName.filter { $0.kind == .func }
            let funcsCandidates = funcs.compactMap { matchFunction($0, arguments: arguments) }

            let types = symbolsWithName.filter { $0.kind == .class || $0.kind == .struct || $0.kind == .enum || $0.kind == .extension }
            var initsCandidates: [(Symbol, TypeSignature)] = []
            for type in types {
                let typeSignature = type.typeSignature(symbols: symbols)
                for relationship in type.relationships {
                    guard relationship.kind == .memberOf && relationship.isInverse else {
                        continue
                    }
                    guard let member = lookup(identifier: relationship.targetIdentifier ?? ""), member.kind == .`init` else {
                        continue
                    }
                    guard let (symbol, signature) = matchFunction(member, arguments: arguments), case .function(let argumentTypes, _) = signature else {
                        continue
                    }
                    // Remap return type of .init from .void to owning type
                    initsCandidates.append((symbol, .function(argumentTypes, typeSignature)))
                }
            }
            return ranked(funcsCandidates + initsCandidates, keyPath: \.0).map(\.signature)
        }

        /// Return the signatures of the possible subscripts being called with the given arguments.
        func subscriptSignature(in type: TypeSignature, arguments: [LabeledValue<TypeSignature>]) -> [TypeSignature] {
            if case .array(let elementType) = type, arguments.count == 1 {
                return [.function([.int], elementType)]
            } else if case .dictionary(let keyType, let valueType) = type, arguments.count == 1 {
                return [.function([keyType], valueType)]
            }

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
            let candidates = ranked(lookup(name: typeName))
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
                    guard relationship.isInverse, let memberSymbol = lookup(identifier: relationship.targetIdentifier ?? ""), memberSymbol.name == member else {
                        break
                    }
                    return memberSymbol.typeSignature(symbols: symbols)
                case .inheritsFrom:
                    guard !relationship.isInverse, let inheritsFrom = lookup(identifier: relationship.targetIdentifier ?? "") else {
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
            let candidates = ranked(lookup(name: typeName))
            var functions: [(symbol: Symbol, signature: TypeSignature)] = []
            for candidate in candidates {
                for function in functionSignature(of: name, in: candidate, arguments: arguments) {
                    if !functions.contains(where: { $0.signature == function.signature }) {
                        functions.append(function)
                    }
                }
            }
            return ranked(functions, keyPath: \.0).map(\.signature)
        }

        private func functionSignature(of name: String, in candidate: Symbol, arguments: [LabeledValue<TypeSignature>]) -> [(symbol: Symbol, signature: TypeSignature)] {
            var functions: [(symbol: Symbol, signature: TypeSignature)] = []
            for relationship in candidate.relationships {
                switch relationship.kind {
                case .memberOf:
                    guard relationship.isInverse, let member = lookup(identifier: relationship.targetIdentifier ?? ""), member.name == name else {
                        break
                    }
                    if let function = matchFunction(member, arguments: arguments) {
                        functions.append(function)
                    }
                case .inheritsFrom:
                    guard !relationship.isInverse, let inheritsFrom = lookup(identifier: relationship.targetIdentifier ?? "") else {
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
            let (parameters, returnType) = symbol.functionSignature(symbols: symbols)
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
                matchingParameterTypes.append(parameters[matchingIndex].type.or(argument.value))
                parameterIndex = matchingIndex + 1
            }
            // Make sure there are no more required parameters
            if parameterIndex < parameters.count {
                if parameters[parameterIndex...].contains(where: { !$0.hasDefaultValue }) {
                    return nil
                }
            }
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
                    if parameter.label == "_" && parameter.type.isCompatible(with: argument.value) {
                        return startIndex + index
                    } else if case .function = parameter.type, parameter.type.isCompatible(with: argument.value) {
                        return startIndex + index
                    } else if !parameter.hasDefaultValue {
                        return nil
                    }
                }
            }
            return nil
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

/// A code symbol.
struct Symbol {
    let symbol: UnifiedSymbolGraph.Symbol
    let name: String
    let moduleName: String
    let sourceURL: URL?
    fileprivate(set) var relationships: [Relationship] = []

    private let selector: UnifiedSymbolGraph.Selector
    private let mixins: [String: Mixin]
    private let declarationFragments: SymbolGraph.Symbol.DeclarationFragments

    fileprivate init?(symbol: UnifiedSymbolGraph.Symbol, moduleName: String) {
        guard let selector = symbol.names.keys.first(where: { $0.interfaceLanguage == "swift" }) else {
            return nil
        }
        guard let mixins = symbol.mixins[selector] else {
            return nil
        }
        guard let declarationFragments = mixins[SymbolGraph.Symbol.DeclarationFragments.mixinKey] as? SymbolGraph.Symbol.DeclarationFragments else {
            return nil
        }

        if symbol.kind[selector]?.identifier == .`init` {
            self.name = "init"
        } else if symbol.kind[selector]?.identifier == .subscript {
            self.name = "subscript"
        } else {
            guard let name = declarationFragments.declarationFragments.first(where: { $0.kind == .identifier })?.spelling else {
                return nil
            }
            self.name = name
        }
        self.selector = selector
        self.symbol = symbol
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
            let (pts, rt) = functionSignature(symbols: symbols)
            return .function(pts.map { $0.type }, rt)
        case .property:
            fallthrough
        case .var:
            return variableType(symbols: symbols)
        case .protocol:
            return .named(name, [])
        case .struct:
            // Could be array, dictionary so pass through TypeSignature
            return TypeSignature.for(name: name, genericTypes: [])
        default:
            return .none
        }
    }

    func isInDeclaredInheritanceList(typeName: String) -> Bool {
        // We get a fragment like ': AnyObject'
        for fragment in declarationFragments.declarationFragments {
            guard fragment.spelling.contains(":") else {
                continue
            }
            return fragment.spelling.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ":" }).map({ String($0) }).contains(typeName)
        }
        return false
    }

    var isVariableReadWrite: Bool {
        return !declarationFragments.hasKeyword("let") && (!declarationFragments.hasKeyword("get") || declarationFragments.hasKeyword("set"))
    }

    var isFunctionMutating: Bool {
        return declarationFragments.hasKeyword("mutating")
    }

    func variableType(symbols: Symbols) -> TypeSignature {
        guard let typeIndex = declarationFragments.declarationFragments.firstIndex(where: { $0.spelling.hasPrefix(": ") }) else {
            return .none
        }
        let (string, specialFragments) = processFragments(Array(declarationFragments.declarationFragments[typeIndex...]), dropFirst: 2)
        return typeSignature(for: string, specialFragments: specialFragments, symbols: symbols)
    }

    func functionSignature(symbols: Symbols) -> ([Parameter], TypeSignature) {
        guard let typeIndex = declarationFragments.declarationFragments.firstIndex(where: { $0.spelling.hasPrefix("(") }) else {
            return ([], .none)
        }
        let (string, specialFragments) = processFragments(Array(declarationFragments.declarationFragments[typeIndex...]))
        return functionSignature(for: string, specialFragments: specialFragments, symbols: symbols)
    }

    private func processFragments(_ fragments: [SymbolGraph.Symbol.DeclarationFragments.Fragment], dropFirst: Int = 0) -> (String, [Int: SymbolGraph.Symbol.DeclarationFragments.Fragment]) {
        var specialFragments: [Int: SymbolGraph.Symbol.DeclarationFragments.Fragment] = [:]
        var string = ""
        for (index, fragment) in fragments.enumerated() {
            if fragment.kind != .text {
                specialFragments[string.count] = fragment
                string += fragment.spelling
            } else if index == 0 {
                string += fragment.spelling.dropFirst(dropFirst)
            } else {
                string += fragment.spelling
            }
        }
        return (string, specialFragments)
    }

    private func functionSignature(for string: String, specialFragments: [Int: SymbolGraph.Symbol.DeclarationFragments.Fragment], symbols: Symbols) -> ([Parameter], TypeSignature) {
        let s = Array(string)
        var i = 0
        var parameters: [Parameter] = []
        var parameter: Parameter? = nil
        var returnType: TypeSignature = .void
        var skippingDefaultValue = false
        var defaultValueParenthesesDepth = 0
        var inString = false
        var backslashCount = 0
        outer: while i < s.count {
            if let fragment = specialFragments[i] {
                switch fragment.kind {
                case .externalParameter:
                    if let parameter {
                        parameters.append(parameter)
                    }
                    skippingDefaultValue = false
                    // Each parameter starts with an externalParameter fragment for its label
                    parameter = Parameter(label: fragment.spelling, hasDefaultValue: false, type: .none)
                    fallthrough
                case .internalParameter:
                    // Skip over the fragment and check for a declared type
                    i += fragment.spelling.count
                    if i < s.count && s[i] == ":" {
                        let (type, endIndex) = typeSignature(for: s, startIndex: i + 1, specialFragments: specialFragments, symbols: symbols)
                        if let type {
                            parameter?.type = type
                        }
                        i = endIndex
                    }
                    continue outer
                case .keyword:
                    i += fragment.spelling.count
                    continue outer
                default:
                    break
                }
            }

            switch s[i] {
            case "\\":
                if inString {
                    backslashCount += 1
                }
            case "\"":
                if inString {
                    if backslashCount % 2 == 0 {
                        inString = false
                    }
                } else {
                    inString = true
                }
            case "=":
                if inString || skippingDefaultValue {
                    break
                }
                parameter?.hasDefaultValue = true
                skippingDefaultValue = true
            case "(":
                if inString {
                    break
                }
                if skippingDefaultValue {
                    defaultValueParenthesesDepth += 1
                }
            case ")":
                if inString {
                    break
                }
                if skippingDefaultValue && defaultValueParenthesesDepth > 0 {
                    defaultValueParenthesesDepth -= 1
                } else {
                    // This should mark the end of the parameters
                    if let parameter {
                        parameters.append(parameter)
                    }
                    if i + 3 < s.count && s[i + 1] == " " && s[i + 2] == "-" && s[i + 3] == ">" {
                        returnType = typeSignature(for: s, startIndex: i + 4, specialFragments: specialFragments, symbols: symbols).0?.or(.void) ?? .void
                    }
                    break outer
                }
            default:
                break
            }

            if s[i] != "\\" {
                backslashCount = 0
            }
            i += 1
        }
        return (parameters, returnType)
    }

    private func typeSignature(for string: String, specialFragments: [Int: SymbolGraph.Symbol.DeclarationFragments.Fragment], symbols: Symbols) -> TypeSignature {
        let (type, _) = typeSignature(for: Array(string), startIndex: 0, specialFragments: specialFragments, symbols: symbols)
        return type ?? .none
    }

    private func typeSignature(for s: [Character], startIndex: Int, specialFragments: [Int: SymbolGraph.Symbol.DeclarationFragments.Fragment], symbols: Symbols) -> (TypeSignature?, Int) {
        var i = startIndex
        var types: [TypeSignature] = []
        var genericTypes: [TypeSignature] = []
        var returnType: TypeSignature? = nil
        var inParentheses = false
        var inBraces = false
        var inGenerics = false
        var isOptional = false
        outer: while i < s.count {
            if let fragment = specialFragments[i] {
                switch fragment.kind {
                case .typeIdentifier:
                    let type = fragment.typeSignature(symbols: symbols)
                    if inGenerics {
                        genericTypes.append(type)
                    } else {
                        types.append(type)
                    }
                    i += fragment.spelling.count
                    continue outer
                case .keyword:
                    i += fragment.spelling.count
                    continue outer
                default:
                    break
                }
            }

            switch s[i] {
            case "[":
                inBraces = true
                let (type, endIndex) = typeSignature(for: s, startIndex: i + 1, specialFragments: specialFragments, symbols: symbols)
                if let type {
                    types.append(type)
                }
                i = endIndex
            case "]":
                if inBraces {
                    i += 1
                }
                if i < s.count && s[i] == "?" {
                    isOptional = true
                    i += 1
                }
                break outer
            case "(":
                inParentheses = true
                let (type, endIndex) = typeSignature(for: s, startIndex: i + 1, specialFragments: specialFragments, symbols: symbols)
                if let type {
                    types.append(type)
                }
                i = endIndex
            case ")":
                if inParentheses {
                    if i + 3 < s.count && s[i + 1] == " " && s[i + 2] == "-" && s[i + 3] == ">" {
                        let (type, endIndex) = typeSignature(for: s, startIndex: i + 4, specialFragments: specialFragments, symbols: symbols)
                        if let type {
                            returnType = type
                        }
                        i = endIndex
                    } else {
                        i += 1
                        if i < s.count && s[i] == "?" {
                            isOptional = true
                            i += 1
                        }
                    }
                }
                break outer
            case "<":
                inGenerics = true
                let (type, endIndex) = typeSignature(for: s, startIndex: i + 1, specialFragments: specialFragments, symbols: symbols)
                if let type {
                    genericTypes.append(type)
                }
                i = endIndex
            case ">":
                if inGenerics {
                    i += 1
                    if i < s.count && s[i] == "?" {
                        isOptional = true
                        i += 1
                    }
                }
                break outer
            case "?":
                if inGenerics, let type = genericTypes.last {
                    genericTypes[genericTypes.count - 1] = .optional(type)
                } else if !inGenerics, let type = types.last {
                    types[types.count - 1] = .optional(type)
                }
                i += 1
            default:
                if inBraces || inParentheses || inGenerics || s[i].isWhitespace {
                    i += 1
                } else {
                    break outer
                }
            }
        }

        var type: TypeSignature? = nil
        if inBraces {
            if !types.isEmpty {
                type = types.count == 1 ? .array(types[0]) : .dictionary(types[0], types[1])
                if isOptional {
                    type = .optional(type!)
                }
            }
        } else if inParentheses {
            if let returnType {
                type = .function(types, returnType)
                if isOptional {
                    type = .optional(type!)
                }
            } else if !types.isEmpty {
                type = .tuple(Array<String?>(repeating: nil, count: types.count), types)
                if isOptional {
                    type = .optional(type!)
                }
            } else {
                type = .void // ()
            }
        } else if !types.isEmpty {
            if case .named(let name, _) = types[0] {
                type = .named(name, genericTypes)
            } else {
                type = types[0]
            }
            if isOptional {
                type = .optional(type!)
            }
        }
        return (type, i)
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
        var label: String
        var hasDefaultValue: Bool
        var type: TypeSignature
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
