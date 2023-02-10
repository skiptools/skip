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

    private var moduleInfos: [String: ModuleInfo] = [:]

    public init(moduleName: String, graphs: [String: UnifiedSymbolGraph]) {
        self.moduleName = moduleName
        for entry in graphs {
            let moduleInfo = Self.processModuleGraph(entry.value, publicOnly: entry.key != moduleName)
            moduleInfos[entry.key] = moduleInfo
        }
    }

    private static func processModuleGraph(_ graph: UnifiedSymbolGraph, publicOnly: Bool) -> ModuleInfo {
        let moduleInfo = ModuleInfo()
        for entry in graph.symbols {
            guard let symbolInfo = processSymbol(entry.value, publicOnly: publicOnly) else {
                continue
            }
            moduleInfo.addSymbol(symbolInfo, identifier: entry.key)
        }
        return moduleInfo
    }

    private static func processSymbol(_ symbol: UnifiedSymbolGraph.Symbol, publicOnly: Bool) -> SymbolInfo? {
        guard let selector = symbol.accessLevel.keys.first(where: { $0.interfaceLanguage == "swift" }) else {
            return nil
        }
        //~~~
        // TODO: Will this skip default public members? e.g. members of a public protocol
        guard !publicOnly || symbol.accessLevel[selector]?.rawValue == "public" || symbol.accessLevel[selector]?.rawValue == "open" else {
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
        case .`init`:
            print("INIT")
        case .extension:
            print("EXTENSION")
        case .method:
            print("METHOD")
        case .operator:
            print("OPERATOR")
        case .property:
            print("PROPERTY")
        case .protocol:
            print("PROTOCOL")
        case .struct:
            print("STRUCT")
        case .subscript:
            print("SUBSCRIPT")
        case .var:
            print("VAR")
        default:
            print("UNKNOWN SYMBOL KIND: \(kind.identifier)")
        }
        print("SYMBOL: \(symbol)")
        return nil
    }

    class ModuleInfo {
        func addSymbol(_ symbol: SymbolInfo, identifier: String) {

        }
    }

    struct SymbolInfo {

    }
}
