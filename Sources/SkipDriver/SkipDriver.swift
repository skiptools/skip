// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor SkipDriver {
    /// Executes `skiptool info` and returns the info dictionary.
    public static func skipInfo(messageHandler: (NSDictionary) -> () = { _ in }) async throws -> NSDictionary {
        var results: [NSDictionary] = []

        for try await result in try execSkip(["info", "-j"]) {
            // log messages are indicated by a "message" and "kind" field
            if let message = result["message"] as? String,
               let kind = result["kind"] as? String {
                let (_, _) = (kind, message)
                //print("log:", result)
                messageHandler(result)
            } else {
                results.append(result)
            }
        }

        guard let result = results.last else {
            throw SkipDriverError.commandNoResult(cmd: "skiptool")
        }

        return result
    }

    /// Forks the given command and returns an async stream of parsed JSON messages, one dictionary for each line of output.
    public static func execSkip(_ arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment, workingDirectory: URL? = nil) throws -> AsyncThrowingCompactMapSequence<AsyncThrowingStream<Data, Swift.Error>, NSDictionary> {
        let skiptool = try findSkipTool()
        return Process.streamJSON(command: [skiptool.path] + arguments, environment: environment, workingDirectory: workingDirectory, onExit: Process.expectZeroExitCode)
    }

    /// Returns the tool path against a base URL, either embedded with the downloaded `skiptool.artifactbundle` or directly against a build folder.
    static func skipToolExecutable(inArtifact: Bool, base: URL) throws -> URL {
        let basePath = inArtifact ? "artifacts/skip/skiptool.artifactbundle/" : ""
        let toolPath = basePath + "skiptool"
        let toolURL = URL(fileURLWithPath: toolPath, relativeTo: base)
        if !FileManager.default.isExecutableFile(atPath: toolURL.path) {
            throw SkipDriverError.toolPathNotFound(toolURL)
        }
        return toolURL
    }

    /// Finds the given tool in the current process' `PATH`.
    public static func findSkipTool(isSkipLocal: Bool? = nil) throws -> URL {
        // there are 6 scenarios to handle, all of which will store the skiptool in different locations:
        // XCode: NON-LOCAL/RELEASE  => (downloaded skip.artifactbundle)
        // XCode: SKIPLOCAL/DEBUG    => (local debug skiptool)
        // XCode: SKIPLOCAL/RELEASE  => (local release skiptool)
        // SPM:   NON-LOCAL/RELEASE  => (downloaded skip.artifactbundle)
        // SPM:   SKIPLOCAL/DEBUG    => (local debug skiptool)
        // SPM:   SKIPLOCAL/RELEASE  => (local release skiptool)
        let env = ProcessInfo.processInfo.environment

        let isSkipLocal = isSkipLocal ?? (env["SKIPLOCAL"] != nil)
        let xcodeBuildFolder = env["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? env["BUILT_PRODUCTS_DIR"]

        switch (isSkipLocal, xcodeBuildFolder) {
        case (false, .none): // non-local SPM
            // check the local SPM build folder
            let buildDir = URL(fileURLWithPath: ".build", isDirectory: true)
            return try skipToolExecutable(inArtifact: !isSkipLocal, base: buildDir)

        case (true, .none): // local SPM
#if DEBUG
            let buildDir = URL(fileURLWithPath: ".build/debug", isDirectory: true)
#else
            let buildDir = URL(fileURLWithPath: ".build/release", isDirectory: true)
#endif
            return try skipToolExecutable(inArtifact: !isSkipLocal, base: buildDir)

        case (true, .some(let xcodeFolder)): // local Xcode
            // when we are in Xcode with SKIPLOCAL set, so we check for the locally-built version
            // of the tool
            let productsFolder = URL(fileURLWithPath: xcodeFolder, isDirectory: true)
            return try skipToolExecutable(inArtifact: !isSkipLocal, base: productsFolder)

        case (false, .some(let xcodeFolder)): // non-local Xcode
            // we are in Xcode with non-local tool dependency;
            // the two options are the binary artifact download or the source build
            // the artifact package will be located in the derived data path
            // when running against a local source build, the compiled artifact will be at: .build/debug/skiptool
            let productsFolder = URL(fileURLWithPath: xcodeFolder, isDirectory: true)
            let baseFolder = productsFolder  // ~/Library/Developer/Xcode/DerivedData/prod-id/Build/Products/Debug
                .deletingLastPathComponent() // ~/Library/Developer/Xcode/DerivedData/prod-id/Build/Products
                .deletingLastPathComponent() // ~/Library/Developer/Xcode/DerivedData/prod-id/Build
                .deletingLastPathComponent() // ~/Library/Developer/Xcode/DerivedData/prod-id/
                .appendingPathComponent("SourcePackages", isDirectory: true)
            return try skipToolExecutable(inArtifact: !isSkipLocal, base: baseFolder)
        }
    }
}

public enum SkipDriverError : Error, LocalizedError {
    case toolPathNotFound(URL)
    case commandNoResult(cmd: String)

    public var errorDescription: String? {
        switch self {
        case .toolPathNotFound(let url):
            return "Could not located tool path from \(url.path)"
        case .commandNoResult(let cmd):
            return "The command returned no output: \(cmd)"
        }
    }
}

