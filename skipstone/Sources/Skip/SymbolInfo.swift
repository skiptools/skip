import SymbolKit

/// Provides information about code symbols.
///
/// Currently an abstraction over `SymbolKit`.
///
/// The build artifacts required to extract symbol information are not always present for build plugins or command line tools, so all symbol
/// info is optional for operations other than final transpilation.
public struct SymbolInfo {
    public init(graphs: [String: UnifiedSymbolGraph]) {

    }
}
