import Foundation
import SkipSyntax
import SymbolKit

fileprivate let logger = Logger(subsystem: "skip", category: "symbols")

/// A cache of symbols
public actor SymbolCache {
    private var cache: [SymbolKey: [URL: SymbolGraph]] = [:]

    public init() {
    }

    private struct SymbolKey : Hashable {
        let moduleName: String
        let accessLevel: String
    }

    #if os(macOS) || os(Linux)
    public func symbols(for moduleName: String, accessLevel: String = "internal") async throws -> [URL: SymbolGraph] {
        let key = SymbolKey(moduleName: moduleName, accessLevel: accessLevel)
        if let symbols = cache[key] {
            return symbols
        }

        let symbols = try await SkipSystem.extractSymbols(moduleFolder: .moduleBuildFolder(), moduleNames: [moduleName], accessLevel: accessLevel)
        guard !symbols.isEmpty else {
            struct NoSymbolsFoundError : Error { }
            throw NoSymbolsFoundError()
        }
        cache[key] = symbols
        return symbols
    }
    #endif
}

/// Pared-down contents of the JSON output of `swiftc -print-target-info`
struct SwiftTarget: Codable {
    struct Target: Codable {
        let triple: String
        let unversionedTriple: String
        let moduleTriple: String
    }

    let compilerVersion: String?

    let target: Target
}
