import Foundation
import SkipSyntax
import SymbolKit
import TSCBasic
#if canImport(Cocoa)
import class Cocoa.NSWorkspace
#endif

#if os(macOS) || os(Linux)
public struct SkipSystem {
    /// Takes the Swift file at the given URL and compiles it with the parameters for extracting symbols, and then returns the parsed symbol graph.
    ///
    /// - Parameters:
    ///   - url: the URL of the Swift file to compile. If this is a `Package.swift` file, then the build will be run with `swift build`, otherwise it will use `swiftc` for a single file.
    ///   - accessLevel: the default access level for the generated symbols
    /// - Returns: the parsed SymbolGraph that resulted from the compilation
    public static func buildSymbols(swift swiftFileURL: URL, singlePass: Bool = false, sdk: String = "macosx", moduleName: String? = nil, accessLevel: String = "private") async throws -> SymbolGraph? {
        // symbolgraph-extract implementation:
        // https://github.com/apple/swift-package-manager/blob/main/Sources/Commands/Utilities/SymbolGraphExtract.swift

        // an alternative way to run this could be: `swift package dump-symbol-graph --minimum-access-level private`

        // another alternative could be to fork `swift build` against a Package.swift
        // https://www.swift.org/documentation/docc/documenting-a-swift-framework-or-package#Create-Documentation-for-a-Swift-Package
        // swift build --target DeckOfPlayingCards -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc .build
        // this is based on how docc gathers symbols: https://github.com/apple/swift-docc/blob/main/Sources/generate-symbol-graph/main.swift#L157
        // e.g.: swift build -Xswiftc -emit-symbol-graph -Xswiftc -emit-symbol-graph-dir -Xswiftc ./.build/ -Xswiftc -symbol-graph-minimum-access-level -Xswiftc private
        // but we also omit synthesized members because they blow up the symbol graph size of any SwiftUI view

        let urlBase = swiftFileURL.deletingPathExtension()
        let moduleName = moduleName ?? urlBase.lastPathComponent // if the module name is not set, default to the last part of the URL
        let dir = urlBase.deletingLastPathComponent()

        // construct a command like: xcrun swift -frontend -target $(swiftc -print-target-info | jq -r .target.triple) -sdk $(xcrun --show-sdk-path --sdk macosx) -D DEBUG  -module-name Source -emit-module-path Source.swiftmodule Source.swift

        // first get the correct sdk and target info, a la: swiftc -module-name Source -emit-module-path . Source.swift && swift symbolgraph-extract -output-dir . -target $(swiftc -print-target-info | jq -r .target.triple) -sdk $(xcrun --show-sdk-path --sdk macosx) -minimum-access-level internal -I . -module-name Source

        // get the target info from the JSON emitted from `swift -print-target-info` (e.g., "arm64-apple-macosx13.0")
        let targetInfoData = try await xcrun("swift", "-print-target-info")
        let targetInfo = try JSONDecoder().decode(SwiftTarget.self, from: Data(targetInfoData.utf8))

        // get the SDK path (e.g., for "xcrun --show-sdk-path --sdk macosx" it might return "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.1.sdk")
        let sdKPath = try await xcrun("--show-sdk-path", "--sdk", sdk)

        let modulePath = urlBase.appendingPathExtension("swiftmodule").path

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
                        "-skip-synthesized-members",
                        //"-v", // verbose
                        //"-pretty-print",
                        //"-skip-synthesized-members",
                        "-output-dir", dir.path,
                        "-target", targetInfo.target.triple,
                        "-sdk", sdKPath,
                        "-minimum-access-level", accessLevel,
                        "-I", dir.path)

        let symbolFile = urlBase.appendingPathExtension("symbols.json")
        let graphData = try Data(contentsOf: symbolFile)
        let graph = try JSONDecoder().decode(SymbolGraph.self, from: graphData)
        return graph
    }

    /// A serialize form of a `Package.swift` file, as output by `/usr/bin/xcrun swift package --package-path . dump-package`
    public struct PackageSwift : Decodable {
        public let name: String?
        public struct PackageKind : Decodable {
            var root: [String]
        }
        public let packageKind: PackageKind?
        public let cLanguageStandard: String?
        public let cxxLanguageStandard: String?
        public let pkgConfig: String?
        public struct PackageDependency : Decodable {
            public struct SourceControl : Decodable {
                public let identity: String
                public struct SourceLocation : Decodable {
                    public let remote: [String]? // e.g. "https://github.com/apple/swift-syntax.git"
                }
                public let location: SourceLocation
                public let productFilter: String?
                public struct Requirement : Decodable {
                    public let branch: [String]? // e.g., ["main"]
                    public struct VersionRange : Decodable {
                        public let lowerBound: String // e.g. "1.0.0"
                        public let upperBound: String // e.g. "2.0.0"
                    }
                    /// A package specifying `from: "1.0.0"` will result in a package range of "1.0.0" - "2.0.0"
                    public let range: [VersionRange]?
                }
                public let requirement: Requirement
            }
            public let sourceControl: [SourceControl]?
        }
        public let dependencies: [PackageDependency]
        public struct PackagePlatform : Decodable {
            public let platformName: String // e.g., "macos", "ios"
            public let version: String // e.g., "13.0", "16.0"
        }
        public let platforms: [PackagePlatform]
        public struct PackageProduct : Decodable {
            public let name: String
            public let targets: [String]
        }
        public let products: [PackageDependency]
        public struct PackageTarget : Decodable {
            public let name: String
            public let type: String // e.g. "regular", "test", "executable", "plugin"

            public struct PackageTargetDependency : Decodable {
                public let product: [String?]? // e.g. ["SwiftSyntax", "swift-syntax", null, null]
                public let byName: [String?]? // e.g. ["SwiftSyntax", null]
            }
            public let dependencies: [PackageTargetDependency]?
            public let exclude: [String]?
            public struct PackageTargetResource : Decodable {
                public let path: String
                //public let rule: ResourceRule
            }
            public let resources: [PackageTargetResource]?
            //public let settings: [String]
        }
        public let targets: [PackageTarget]
        public struct ToolsVersion : Decodable {
            public let _version: String // e.g. "5.7.0"
        }
        public let toolsVersion: ToolsVersion
    }

    /// Parses the package swift in the given folder and returns the deserialized structure from the JSON
    public static func parsePackageSwift(path: URL) async throws -> PackageSwift {
        // there's a quick with executing swift package from the test case: the first line when there is a branch is "error: 'pkgtest': Invalid branch name: 'main'" and it fails with error code 1
        var jsonLines = try await xcrun(permitFailure: true, "swift", "package", "--package-path", path.path, "dump-package").split(separator: "\n")
        while jsonLines.first?.hasPrefix("{") == false {
            jsonLines.remove(at: 0)
        }

        let json = jsonLines.joined(separator: "\n")
        let decoder = JSONDecoder()
        return try decoder.decode(PackageSwift.self, from: Data(json.utf8))
    }

    /// Extracts the symbols for all the named modules
    public static func extractSymbolGraph(moduleFolder moduleBuildFolder: URL? = nil, moduleNames: [String], from moduleURL: URL) async throws -> (unifiedGraphs: [String: UnifiedSymbolGraph], graphSources: [String: [GraphCollector.GraphKind]]) {
        // gather the symbols for all the targets
        let collector = GraphCollector(extensionGraphAssociationStrategy: .extendingGraph)
        for moduleName in moduleNames {
            let symbolGraphs = try await SkipSystem.extractSymbols(moduleFolder: moduleBuildFolder ?? URL.moduleBuildFolder(), moduleNames: [moduleName])
            for (url, graph) in symbolGraphs {
                logger.debug("adding symbol graph for: \(url.path)")
                collector.mergeSymbolGraph(graph, at: url)
            }
        }
        let (unifiedGraphs, graphSources) = collector.finishLoading()
        return (unifiedGraphs, graphSources)
    }

    public static func extractSymbols(moduleFolder moduleBuildFolder: URL? = nil, moduleNames: [String], tmpDir: URL? = nil, sdk: String = "macosx", accessLevel: String = "internal") async throws -> [URL: SymbolGraph] {
        let moduleBuildFolder = moduleBuildFolder ?? URL.moduleBuildFolder()

        // fall back to using a temporary folder
        let tmpDir = tmpDir ?? URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // get the target info from the JSON emitted from `swift -print-target-info` (e.g., "arm64-apple-macosx13.0")
        let targetInfoData = try await xcrun("swift", "-print-target-info")
        let targetInfo = try JSONDecoder().decode(SwiftTarget.self, from: targetInfoData.data(using: .utf8)!)

        // get the SDK path (e.g., for "xcrun --show-sdk-path --sdk macosx" it might return "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.1.sdk")
        let sdKPath = try await xcrun("--show-sdk-path", "--sdk", sdk)

        var modulePaths: [URL: SymbolGraph] = [:]

        for moduleName in moduleNames {
            let modulePath = moduleBuildFolder.appendingPathComponent(moduleName).appendingPathExtension("swiftmodule")

            if !FileManager.default.isReadableFile(atPath: modulePath.path) {
                // permit missing modules; this is so SkipLib does not need to be a swift dependency of other packages
                logger.warning("missing module at path: \(modulePath.path)")
                if modulePath.lastPathComponent != "SkipLib.swiftmodule" {
                    throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: modulePath.path])
                }
                return [:]
            }

            _ = try await xcrun("swift",
                                "symbolgraph-extract",
                                "-module-name", moduleName,
                                "-include-spi-symbols",
                                "-skip-inherited-docs",
                                "-skip-synthesized-members",
                                //"-v", // verbose
                                //"-pretty-print",
                                //"-skip-synthesized-members",
                                "-output-dir", tmpDir.path,
                                "-target", targetInfo.target.triple,
                                "-sdk", sdKPath,
                                "-minimum-access-level", accessLevel,
                                "-F", "\(sdKPath)/../../Library/Frameworks/", // needed for XCTest imports
                                "-I", moduleBuildFolder.path)

            // load the symbol file, as well as any associated extensions with @ suffixes
            for fileURL in try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: [.isDirectoryKey]) {
                let fileName = fileURL.lastPathComponent
                if fileName.hasPrefix(moduleName) && fileName.hasSuffix(".symbols.json") {
                    let graphData = try Data(contentsOf: fileURL)
                    let graph = try JSONDecoder().decode(SymbolGraph.self, from: graphData)
                    modulePaths[fileURL] = graph
                }
            }
        }

        return modulePaths
    }

    @discardableResult static func xcrun(permitFailure: Bool = false, _ args: String...) async throws -> String {
#if os(macOS)
        // use xcrun, which will use whichever Swift we have set up with Xcode
        let runcmd = "/usr/bin/xcrun"
#elseif os(Linux)
        // use `env` to resolve the swift/swiftc command in the current environment
        let runcmd = "/usr/bin/env"
#else
#error("unsupported platform")
#endif

        let result = try await Process.popen(arguments: [runcmd] + args)
        return try result.utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SkipSystem {
    /// The output folder name for the kotlin interop project (kip)
    //#if DEBUG
    public static let kipFolderName = "kip"
    //#else
    //// the folder should go in the .build directory for release builds
    //public static let kipFolderName = ".build/skipped"
    //#endif

    /// The bundle identifier for the Android Studio.app installation
    public static let androidStudioBundleID = "com.google.android.studio"

    static let logger = Logger(subsystem: "skip", category: "assembler")

    /// Returns the home folder for the local Android Studio install based on the bundle ID (`com.google.android.studio`), which contains `kotlinc` and gradle libraries.
    ///
    /// Android Studio can be downloaded and installed from https://developer.android.com/studio/
    static func studioRoot(bundleID: String) throws -> URL {
        struct BundleIDNotFound : LocalizedError {
            let failureReason: String? = "Android Studio not found; install from: https://developer.android.com/studio/"
        }
#if canImport(Cocoa)
        // urlForApplication can fail in sandboxed environments, so we can fall back to just checking the hardcoded location
        let appLocation = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) ?? URL(fileURLWithPath: "/Applications/Android Studio.app", isDirectory: true)
        return appLocation
#else
        // TODO: figure out how to find studio in Linux
        throw BundleIDNotFound()
#endif
    }

    static var kotlinCompiler: URL {
        get throws {
            // e.g.: /Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc/bin/kotlinc
            URL(fileURLWithPath: "Contents/plugins/Kotlin/kotlinc/bin/kotlinc", isDirectory: false, relativeTo: try studioRoot(bundleID: androidStudioBundleID))
        }
    }

    /// Forks the
    /// - Parameters:
    ///   - studioID: the ID of the app container for the `kotlinc` command
    ///   - script: the script to execute
    /// - Returns: the string result of the script
    public static func kotlinc(script: String) async throws -> String {
        try await Process.popen(arguments: ["/bin/sh", kotlinCompiler.path, "-e", script])
            .utf8Output()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts the given Kotlin script to JavaScript.
    public static func kotlinToJS(_ kotlin: String, legacy: Bool = true, cleanup: Bool = true) async throws -> String {
        var env: [String: String] = [:]
        // activates Kotlin->JavaScript mode
        env["KOTLIN_COMPILER"] = "org.jetbrains.kotlin.cli.js.K2JSCompiler"

        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { if cleanup { try? FileManager.default.removeItem(at: tmpDir) } }

        let sourceURL = URL(fileURLWithPath: "source.kt", isDirectory: false, relativeTo: tmpDir)
        try kotlin.write(to: sourceURL, atomically: true, encoding: .utf8)
        defer { if cleanup { try? FileManager.default.removeItem(at: sourceURL) } }

        let outputURL = URL(fileURLWithPath: "output.js", isDirectory: false, relativeTo: tmpDir)

        let result = try await Process.popen(arguments: ["/bin/sh",
                                                                  kotlinCompiler.path,
                                                                  legacy ? "-Xuse-deprecated-legacy-compiler" : nil,
                                                                  "-output", outputURL.path,
                                                                  sourceURL.path
                                                                 ].compactMap({ $0 }), environment: env)

        let _ = result

        defer { if cleanup { try? FileManager.default.removeItem(at: outputURL) } }
        return try String(contentsOf: outputURL)
    }
}

#endif

extension URL {
    // FIXME: reduntant with SkipUnit
    /// The folder where built modules will be placed.
    ///
    /// When running within Xcode, which will query the `__XCODE_BUILT_PRODUCTS_DIR_PATHS` environment.
    /// Otherwise, it assumes SPM's standard ".build" folder relative to the working directory.
    static func moduleBuildFolder(debug: Bool? = nil) -> URL {
        // if we are running tests from Xcode, this environment variable should be set; otherwise, assume the .build folder for an SPM build
        let xcodeBuildFolder = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] // also seems to be __XPC_DYLD_LIBRARY_PATH or __XPC_DYLD_FRAMEWORK_PATH; this will be something like ~/Library/Developer/Xcode/DerivedData/MODULENAME-bsjbchzxfwcrveckielnbyhybwdr/Build/Products/Debug


        // FIXME: this is based on the tool's build settings, which will always be release; need a way to determine whether the user's code is debug or release
        #if DEBUG
        let debug = debug ?? true
        #else
        let debug = debug ?? false
        #endif

        let swiftBuildFolder = ".build/" + (debug ? "debug" : "release")
        return URL(fileURLWithPath: xcodeBuildFolder ?? swiftBuildFolder, isDirectory: true)
    }
}

extension FileSystem {
    /// Helper method to recurse the tree and perform the given block on each file.
    ///
    /// Note: `Task.isCancelled` is not checked; the controlling block should check for task cancellation.
    public func recurse(path: AbsolutePath, block: (AbsolutePath) async throws -> ()) async throws {
        let contents = try getDirectoryContents(path)

        for entry in contents {
            let entryPath = path.appending(component: entry)
            try await block(entryPath)
            if isDirectory(entryPath) {
                try await recurse(path: entryPath, block: block)
            }
        }
    }

    /// Output the filesystem tree of the given path.
    public func treeASCIIRepresentation(at path: AbsolutePath = .root) throws -> String {
        var writer: String = ""
        print(".", to: &writer)
        try treeASCIIRepresent(fs: self, path: path, to: &writer)
        return writer
    }

    /// Helper method to recurse and print the tree.
    private func treeASCIIRepresent<T: TextOutputStream>(fs: FileSystem, path: AbsolutePath, prefix: String = "", to writer: inout T) throws {
        let contents = try fs.getDirectoryContents(path)
        // content order is undefined, so we sort for a consistent output
        let entries = contents.sorted()

        for (idx, entry) in entries.enumerated() {
            let isLast = idx == entries.count - 1
            let line = prefix + (isLast ? "└─ " : "├─ ") + entry
            print(line, to: &writer)

            let entryPath = path.appending(component: entry)
            if fs.isDirectory(entryPath) {
                let childPrefix = prefix + (isLast ?  "   " : "│  ")
                try treeASCIIRepresent(fs: fs, path: entryPath, prefix: String(childPrefix), to: &writer)
            }
        }
    }
}

extension AbsolutePath {
    func deletingPathExtension() -> AbsolutePath {
        parentDirectory.appending(component: basenameWithoutExt)
    }

    func appendingPathExtension(_ ext: String) -> AbsolutePath {
        parentDirectory.appending(component: basenameWithoutExt + "." + ext)
    }
}
