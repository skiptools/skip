import SymbolKit

/// Provides information about code symbols.
///
/// Currently an abstraction over `SymbolKit`.
///
/// The build artifacts required to extract symbol information are not always present for build plugins or command line tools, so all symbol
/// info is optional for operations other than final transpilation.
public class SymbolInfo {
    /// The current module name.
    public let moduleName: String

    private var symbolsByIdentifier: [String: Symbol] = [:]
    private var symbolsByName: [String: [Symbol]] = [:]

    public init(moduleName: String, graphs: [String: UnifiedSymbolGraph]) {
        self.moduleName = moduleName
        for entry in graphs {
            dump(entry.value) //~~~
            processGraph(entry.value, module: entry.key)
        }
    }

    private func processGraph(_ graph: UnifiedSymbolGraph, module: String) {
        for entry in graph.symbols {
            guard let symbol = processSymbol(entry.value, module: module) else {
                continue
            }
            symbolsByIdentifier[symbol.identifier] = symbol

            var symbolsWithName = symbolsByName[symbol.name] ?? []
            symbolsWithName.append(symbol)
            symbolsByName[symbol.name] = symbolsWithName
        }
    }

    private func processSymbol(_ symbol: UnifiedSymbolGraph.Symbol, module: String) -> Symbol? {
        guard let selector = symbol.accessLevel.keys.first(where: { $0.interfaceLanguage == "swift" }) else {
            return nil
        }
        let publicOnly = module == moduleName
        guard !publicOnly || symbol.accessLevel[selector]?.rawValue == "public" || symbol.accessLevel[selector]?.rawValue == "open" else {
            return nil
        }

        guard let mixins = symbol.mixins[selector], let declarationFragments = mixins[SymbolGraph.Symbol.DeclarationFragments.mixinKey] as? SymbolGraph.Symbol.DeclarationFragments else {
            return nil
        }
        guard let kind = symbol.kind[selector] else {
            return nil
        }
        switch kind.identifier {
        case .case:
            print("CASE")
        case .class:
            print("CLASS")
        case .enum:
            print("ENUM")
        case .func:
            print("FUNC")
            guard let functionSignature = mixins[SymbolGraph.Symbol.FunctionSignature.mixinKey] as? SymbolGraph.Symbol.FunctionSignature else {
                return nil
            }
        case .`init`:
            print("INIT")
        case .extension:
            print("EXTENSION")
        case .method:
            print("METHOD")
        case .operator:
            print("OPERATOR")
        case .property:
            return Property(symbol: symbol, selector: selector, declarationFragments: declarationFragments)
        case .protocol:
            print("PROTOCOL")
        case .struct:
            print("STRUCT")
        case .subscript:
            print("SUBSCRIPT")
        case .var:
            print("VAR")
        default:
            return nil
        }
        print("SYMBOL: \(symbol)")
        return nil
    }
}

private class Module {
    func addSymbol(_ symbol: Symbol, identifier: String) {

    }
}

private protocol Symbol {

}

private struct Property: Symbol {
    init?(symbol: UnifiedSymbolGraph.Symbol, selector: UnifiedSymbolGraph.Selector, declarationFragments: SymbolGraph.Symbol.DeclarationFragments) {

    }
}

private extension SymbolGraph.Symbol.DeclarationFragments {
    var identifier: String? {
        return declarationFragments.first(where: { $0.kind == .identifier })?.spelling
    }

    func hasKeyword(_ keyword: String) -> Bool {
        return declarationFragments.contains { $0.kind == .keyword && $0.spelling == keyword }
    }
}
