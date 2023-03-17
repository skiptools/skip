import Foundation
import SkipSyntax
import SymbolKit
import TSCBasic
#if canImport(Cocoa)
import class Cocoa.NSWorkspace
#endif

#if os(macOS) || os(Linux)

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
    private func treeASCIIRepresent<T: TextOutputStream>(fs: FileSystem, path: AbsolutePath, localized: Bool = false, prefix: String = "", to writer: inout T) throws {
        let contents = try fs.getDirectoryContents(path)
        // content order is undefined, so we sort for a consistent output
        let entries = localized ? contents.sorted(using: .localizedStandard) : contents.sorted()

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
