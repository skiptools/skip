import Foundation
import Skip
import SymbolKit
import os.log

fileprivate let logger = Logger(subsystem: "skip", category: "symbols")

extension UnifiedSymbolGraph.Symbol {
    /// The location of this symbol, as stored in the `mixins` container.
    public var location: SymbolGraph.Symbol.Location? {
        mixins.values.first?["location"] as? SymbolGraph.Symbol.Location
    }

    /// The fragments of this symbol, as stored in the `mixins` container.
    public var fragments: [SymbolGraph.Symbol.DeclarationFragments.Fragment]? {
        (mixins.values.first?["declarationFragments"] as? SymbolGraph.Symbol.DeclarationFragments)?.declarationFragments
    }
}

/// Position is Equatable but not Hashable
extension SymbolGraph.LineList.SourceRange.Position : Hashable {
    public func hash(into hasher: inout Hasher) {
        self.line.hash(into: &hasher)
        self.character.hash(into: &hasher)
    }
}

extension System {
    /// Takes the Swift file at the given URL and compiles it with the parameters for extracting symbols, and then returns the parsed symbol graph.
    ///
    /// - Parameters:
    ///   - url: the URL of the Swift file to compile. If this is a `Package.swift` file, then the build will be run with `swift build`, otherwise it will use `swiftc` for a single file.
    ///   - accessLevel: the default access level for the generated symbols
    /// - Returns: the parsed SymbolGraph that resulted from the compilation
    public static func buildSymbols(swift swiftFileURL: URL, singlePass: Bool = false, sdk: String = "macosx", moduleName: String? = nil, accessLevel: String = "private") async throws -> SymbolGraph {
        // symbolgraph-extract implementation:
        // https://github.com/apple/swift-package-manager/blob/main/Sources/Commands/Utilities/SymbolGraphExtract.swift

        // an alternative way to run this could be: `swift package dump-symbol-graph --minimum-access-level private`

        // another alternative could be to fork `swift build` against a Package.swift
        // https://www.swift.org/documentation/docc/documenting-a-swift-framework-or-package#Create-Documentation-for-a-Swift-Package
        // swift build --target DeckOfPlayingCards -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc .build
        // this is based on how docc gathers symbols: https://github.com/apple/swift-docc/blob/main/Sources/generate-symbol-graph/main.swift#L157
        // e.g.: swift build -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc ./.build/ -Xswiftc -symbol-graph-minimum-access-level -Xswiftc private

        let urlBase = swiftFileURL.deletingPathExtension()
        let moduleName = moduleName ?? urlBase.lastPathComponent // if the module name is not set, default to the last part of the URL
        let dir = urlBase.deletingLastPathComponent()

        // construct a command like: xcrun swift -frontend -target $(swiftc -print-target-info | jq -r .target.triple) -sdk $(xcrun --show-sdk-path --sdk macosx) -D DEBUG  -module-name Source -emit-module-path Source.swiftmodule Source.swift

        // first get the correct sdk and target info, a la: swiftc -module-name Source -emit-module-path . Source.swift && swift symbolgraph-extract -output-dir . -target $(swiftc -print-target-info | jq -r .target.triple) -sdk $(xcrun --show-sdk-path --sdk macosx) -minimum-access-level internal -I . -module-name Source

        // get the target info from the JSON emitted from `swift -print-target-info` (e.g., "arm64-apple-macosx13.0")
        let targetInfoData = try await xcrun("swift", "-print-target-info").joined(separator: "\n").data(using: .utf8) ?? Data()
        let targetInfo = try JSONDecoder().decode(SwiftTarget.self, from: targetInfoData)

        // get the SDK path (e.g., for "xcrun --show-sdk-path --sdk macosx" it might return "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.1.sdk")
        let sdKPath = try await xcrun("--show-sdk-path", "--sdk", sdk).joined(separator: "\n")

        let modulePath = urlBase.appendingPathExtension("swiftmodule").path

        if singlePass {
            try await xcrun("swift",
                            "-frontend",
                            "-module-name", moduleName,
                            "-target", targetInfo.target.triple,
                            "-sdk", sdKPath,
                            "-emit-module-path", modulePath,
                            "-emit-symbol-graph",
                            "-emit-symbol-graph-dir", dir.path,
                            "-symbol-graph-minimum-access-level", accessLevel,
                            swiftFileURL.path)
        } else {
            try await xcrun("swift",
                            "-frontend",
                            "-module-name", moduleName,
                            "-target", targetInfo.target.triple,
                            "-sdk", sdKPath,
                            "-emit-module-path", modulePath,
                            swiftFileURL.path)
            try await xcrun("swift",
                            "symbolgraph-extract",
                            "-module-name", moduleName,
                            "-include-spi-symbols",
                            "-skip-inherited-docs",
                            //"-v", // verbose
                            //"-pretty-print",
                            //"-skip-synthesized-members",
                            "-output-dir", dir.path,
                            "-target", targetInfo.target.triple,
                            "-sdk", sdKPath,
                            "-minimum-access-level", accessLevel,
                            "-I", dir.path)
        }

        let symbolFile = urlBase.appendingPathExtension("symbols.json")
        let graphData = try Data(contentsOf: symbolFile)
        let graph = try JSONDecoder().decode(SymbolGraph.self, from: graphData)
        return graph
    }

    public static func extractSymbols(_ urlBase: URL, moduleName: String, tmpDir: URL? = nil, sdk: String = "macosx", accessLevel: String = "private") async throws -> [URL: SymbolGraph] {
        // fall back to using a temporary folder
        let tmpDir = tmpDir ?? URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // get the target info from the JSON emitted from `swift -print-target-info` (e.g., "arm64-apple-macosx13.0")
        let targetInfoData = try await xcrun("swift", "-print-target-info").joined(separator: "\n").data(using: .utf8) ?? Data()
        let targetInfo = try JSONDecoder().decode(SwiftTarget.self, from: targetInfoData)

        // get the SDK path (e.g., for "xcrun --show-sdk-path --sdk macosx" it might return "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.1.sdk")
        let sdKPath = try await xcrun("--show-sdk-path", "--sdk", sdk).joined(separator: "\n")

        _ = try await xcrun("swift",
                        "symbolgraph-extract",
                        "-module-name", moduleName,
                        "-include-spi-symbols",
                        "-skip-inherited-docs",
                        //"-v", // verbose
                        //"-pretty-print",
                        //"-skip-synthesized-members",
                        "-output-dir", tmpDir.path,
                        "-target", targetInfo.target.triple,
                        "-sdk", sdKPath,
                        "-minimum-access-level", accessLevel,
                        "-I", urlBase.path)

        let modulePath = urlBase.appendingPathComponent(moduleName).appendingPathExtension("swiftmodule")
        let symbolFile = tmpDir.appendingPathComponent(moduleName).appendingPathExtension("symbols.json")
        let graphData = try Data(contentsOf: symbolFile)
        let graph = try JSONDecoder().decode(SymbolGraph.self, from: graphData)
        // TODO: scan folder for "@" modules for extension loading
        return [modulePath: graph]
    }

    @discardableResult static func xcrun(_ args: String...) async throws -> [String] {
#if os(macOS)
        // use xcrun, which will use whichever Swift we have set up with Xcode
        let runcmd = URL(fileURLWithPath: "/usr/bin/xcrun", isDirectory: false)
#elseif os(Linux)
        // use `env` to resolve the swift/swiftc command in the current environment
        let runcmd = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
#else
#error("unsupported platform")
#endif
        var out: [String] = []
        try await exec(runcmd, arguments: args, environment: nil, workingDirectory: nil, outputHandler: { output in
            //logger.debug("xcrun: \(output)")
            out.append(output)
        })
        return out
    }
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
