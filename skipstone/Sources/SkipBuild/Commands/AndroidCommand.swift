import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ArgumentParser
import SkipSyntax
#if canImport(SkipDriveExternal)
import SkipDriveExternal
fileprivate let androidCommandEnabled = true
#else
fileprivate let androidCommandEnabled = false
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "android",
        abstract: "Perform a native Android package command",
        shouldDisplay: androidCommandEnabled,
        subcommands: [
            AndroidBuildCommand.self,
            AndroidRunCommand.self,
            AndroidTestCommand.self,
        ])

}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
protocol AndroidOperationCommand : MessageCommand, ToolOptionsCommand {
    /// This command's toolchain options
    var toolchainOptions: ToolchainOptions { get }

    /// The arguments to the command to be executed
    var args: [String] { get }
}

fileprivate extension AndroidOperationCommand {
    private func runCommand(command: [String], env: [String: String], with out: MessageQueue) async throws {
        #if !canImport(SkipDriveExternal)
        throw ToolLaunchError(errorDescription: "Cannot launch android command without SkipDriveExternal")
        #else

        for try await outputLine in Process.streamLines(command: command, environment: env, includeStdErr: true, onExit: { result in
            guard case .terminated(0) = result.exitStatus else {
                // we failed, but did not expect an error
                throw AndroidError(errorDescription: "Error \(result.exitStatus) running command: \(command.joined(separator: " "))")
            }
        }) {
            //print(outputLine.line)

            if outputLine.err {
                print(outputLine.line, to: &stderrStream)
                stderrStream.flush()
            } else {
                // squelch common warnings in non-verbose output mode
                if !outputOptions.verbose && (
                    outputLine.line.hasPrefix("warning: Could not read SDKSettings.json for SDK")
                    || outputLine.line.hasPrefix("<unknown>:0: warning: glibc not found for")
                ) {
                    continue
                }

                print(outputLine.line, to: &stdoutStream)
                stdoutStream.flush()
            }
        }
        #endif
    }
    
    /// Run `swift build` for the given Android architectures, optionally running the test cases on the device or copying all the files to the given `archiveOutputFolder`
    func runSwiftPM(cleanup: Bool? = nil, execute executable: String? = nil, remoteFolder: String? = nil, archiveOutputFolder: URL? = nil, with out: MessageQueue) async throws {
        let packageDir = toolchainOptions.packagePath ?? "."
        var architectures = toolchainOptions.arch
        if architectures.isEmpty {
            // pick the default architecture based on the current host; for running executables and tests, this will likely be the one that matches an attached emulator, but for an attached device, we don't know (e.g., an x86_64 host may be connecting to an aarch64 device).
            if ProcessInfo.isARM {
                architectures.append(.aarch64)
            } else {
                architectures.append(.x86_64)
            }
        }

        for arch in architectures {
            let tc = try createToolchainDestinationJSON(for: arch)

            var env: [String: String] = ProcessInfo.processInfo.environmentWithDefaultToolPaths
            let toolchainBin = tc.destination.toolchain.appendingPathComponent("usr/bin")
            let path = toolchainBin.path + ":" + (env["PATH"] ?? "")
            env["PATH"] = path

            let swiftCmd = toolchainBin.appendingPathComponent("swift").path
            if !FileManager.default.fileExists(atPath: swiftCmd) {
                throw CrossCompilerError(errorDescription: "Could not locate swift command at: \(swiftCmd)")
            }
            var cmd: [String] = []

            cmd += [swiftCmd] // causes weird error with the Swift 6 toolchain: "error: invalid absolute path ''"
            //cmd += ["swift"]
            cmd += ["build"]
            cmd += ["--destination", tc.url.path]

            let runTests = cleanup != nil && executable == nil
            if runTests {
                cmd += ["--build-tests"]
            }
            // pass-through the "--verbose" flag to the underlying build command
            if outputOptions.verbose {
                cmd += ["--verbose"]
            }
            // pass-through the "--package-path" flag to the underlying build command
            if let packagePath = toolchainOptions.packagePath {
                cmd += ["--package-path", packagePath]
            }
            // pass-through the "--scratch-path" flag to the underlying build command
            if let scratchPath = toolchainOptions.scratchPath {
                cmd += ["--scratch-path", scratchPath]
            }
            // pass-through the "--configuration" flag to the underlying build command
            if let configuration = toolchainOptions.configuration {
                cmd += ["--configuration", configuration.rawValue]
            }
            // when executable is specified, then the arguments are the command to run;
            // otherwise, they are considered build arguments
            if executable == nil {
                cmd += args
            }
            try await runCommand(command: cmd, env: env, with: out)

            let buildOutputFolder = [
                packageDir,
                toolchainOptions.scratchPath ?? ".build",
                arch.target,
                toolchainOptions.configuration?.rawValue ?? "debug",
            ].joined(separator: "/")

            let buildOutputFolderURL = URL(fileURLWithPath: buildOutputFolder)

            /// Returns all the shared object files that will need to be linked to an binary on Android
            ///
            /// e.g.: `~/Library/Developer/Skip/SDKs/swift-5.10.1-android-24-ndk-27-sdk/usr/lib/aarch64-linux-android/*.so`
            func dependencySharedObjectFiles() throws -> [URL] {
                let libFolder = tc.destination.sdk.appendingPathComponent("usr/lib/" + arch.triple)
                if !FileManager.default.fileExists(atPath: libFolder.path) {
                    throw AndroidError(errorDescription: "Android SDK library folder did not exist at: \(libFolder)")
                }
                // check for .so files like libswift_Concurrency.so or libxml2.so.2.13.3
                // we need to preserve symbolic links because some libraries link to a linked version
                let sharedObjects = try files(at: libFolder, allowLinks: true).filter({ $0.lastPathComponent.contains(".so") })
                return sharedObjects
            }

            if let archiveOutputFolder = archiveOutputFolder {
                let archOutputFolder = archiveOutputFolder.appendingPathComponent(arch.abi)
                //try? FileManager.default.removeItem(at: archiveOutputFolder) // delete any existing archive output folder
                try FileManager.default.createDirectory(at: archOutputFolder, withIntermediateDirectories: true)

                let buildLibraries = try files(at: buildOutputFolderURL).filter({ $0.lastPathComponent.contains(".so") })
                var copyFiles = buildLibraries
                copyFiles += try dependencySharedObjectFiles()

                for so in copyFiles {
                    let dest = archOutputFolder.appendingPathComponent(so.lastPathComponent)
                    try? FileManager.default.removeItem(at: dest) // delete any pre-existing file before copy
                    try FileManager.default.copyItem(at: so, to: dest)
                }
            }

            if executable == nil && runTests == false {
                continue // nothing to do but build, so more on to the next list arch…
            }

            // to figure out the generated test executable name, we need to parse the Package.swift
            let packageManifest = try await parseSwiftPackage(with: out, at: packageDir, swift: swiftCmd)
            let packageName = packageManifest.name

            // take the ./.build/aarch64-unknown-linux-android24/debug/android-native-demoPackageTests.xctest file
            // and copy it with all the dependent .so files to the Android host and execute the test executable
            let executableBase = executable ?? packageName + "PackageTests.xctest"

            let executablePath = buildOutputFolderURL.appendingPathComponent(executableBase)
            if !FileManager.default.isExecutableFile(atPath: executablePath.path) {
                throw AndroidError(errorDescription: "Expected executable did not exist at: \(executablePath.path)")
            }

            // create the list of files that need to be uploaded to the device to run the test cases
            var transferFiles = [executablePath]

            // add any resource folders used by the tests (e.g., "swift-corelibs-foundation_TestFoundation.resources")
            let resources = try dirs(at: buildOutputFolderURL)
                .filter({ $0.pathExtension == "resources" })

            transferFiles += resources

            transferFiles.append(contentsOf: try dependencySharedObjectFiles())

            let adb = try toolOptions.toolPath(for: "adb")
            let stagingDir = remoteFolder ?? "/data/local/tmp/swift-android/" + packageName + "-" + UUID().uuidString + "/"

            // create the staging folder
            await run(with: out, "Connecting to Android", [adb, "shell", "mkdir", "-p", stagingDir], additionalEnvironment: env)

            // Note: one shortcoming of `adb push` is that it doesn't copy symbolic links as links, but insead pushes the underlying file; so, for example, the link libxml2.so -> libxml2.so.2.13.3 will be copies as two separate yet identical files, which increases the size of the transfer unnecessarily. In practice, this isn't a proble, since the linker will work, but it means that the directory of dependent shared objects will be bigger than it needs to be. One workaround to this might be to first archive all the files together (e.g., with tar), transfer the archive, and then unarchive them on the device, but this adds complexity to the process.
            await run(with: out, "Copying \(runTests ? "test" : "executable") files", [adb, "push"] + transferFiles.map(\.path) + [stagingDir], additionalEnvironment: env)

            var runFailure: Error?
            do {
                let testCmd = stagingDir + "/" + executableBase
                // when not running tests, pass through the specified arguments to the command
                let cmdArgs = executable != nil ? args.dropFirst() : []
                // in theory, we should be able to skip individual tests using the _SWIFTPM_SKIP_TESTS_LIST environment variable, but is seems to not work
                //testCmd = "_SWIFTPM_SKIP_TESTS_LIST=TestClass.testName" + " " + testCmd
                try await runCommand(command: [adb, "shell", testCmd] + cmdArgs, env: env, with: out)
            } catch {
                runFailure = error
            }
            // clean up the test folder after running; we can't do this in a defer block, since it is async (and throws)
            // only perform cleanup if the "remote-folder" is unset
            if cleanup == true && remoteFolder == nil {
                try await runCommand(command: [adb, "shell", "rm", "-r", stagingDir], env: env, with: out)
            }
            if let runFailure = runFailure {
                throw runFailure
            }
        }
    }

    /// Create a temporary directory
    func createTempDir() throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory // or URL.temporaryDirectory, but unavailable on Linux
        let tempURL = tmpDir.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        return tempURL
    }
    
    /// Returns true if the given URL is a directory
    /// - Parameters:
    ///   - url: the file URL to check
    ///   - permitLink: if true, then permit folders that are symbolic links to other folders
    func isDir(_ url: URL, permitLink: Bool = true) -> Bool {
        let fm = FileManager.default
        if !url.isFileURL {
            return false
        }
        var isDirectory: ObjCBool = false

        let path = url.path
        if fm.fileExists(atPath: path, isDirectory: &isDirectory) == false {
            return false
        }

        if isDirectory.boolValue == true {
            return true
        }

        if permitLink == true, let linkDestination = (try? fm.destinationOfSymbolicLink(atPath: path)) {
            if fm.fileExists(atPath: linkDestination, isDirectory: &isDirectory) {
                return isDirectory.boolValue == true
            }
        }

        return false
    }

    /// Returns the sorted list of directories at the given location
    func dirs(at url: URL, permitLink: Bool = true) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])
            .filter({ isDir($0, permitLink: permitLink) })
            .sorted { u1, u2 in
                u1.lastPathComponent < u2.lastPathComponent
            }
    }

    /// Returns the sorted list of directories at the given locations
    func dirs(in urls: [URL]) throws -> [URL] {
        try urls.filter({ isDir($0) }).map({ try dirs(at: $0) }).joined().sorted { u1, u2 in
            u1.lastPathComponent < u2.lastPathComponent
        }
    }

    /// Returns the sorted list of regular files at the given locations
    func files(at url: URL, allowLinks: Bool = false) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            .filter({
                if try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    return true
                }
                if try allowLinks == true && $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                    return true
                }
                return false
            })
            .sorted { u1, u2 in
                u1.lastPathComponent < u2.lastPathComponent
            }
    }


    /// Create the destination JSON for cross-compiling to Android
    /// - Returns: the path to the temporary destination file
    func createToolchainDestination(for arch: AndroidArch) throws -> (destination: SerializedDestinationV1, sdk: URL, ndk: URL, toolchain: URL) {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser // or URL.homeDirectory, but unavailable on Linux

        var tc = SerializedDestinationV1()

        let target = arch.target // "aarch64-unknown-linux-android24"
        let triple = arch.triple // "aarch64-linux-android"

        // GH Runner ANDROID_NDK=/Users/runner/Library/Android/sdk/ndk/26.3.11579264
        // https://github.com/actions/runner-images/blob/main/images/macos/macos-13-Readme.md#environment-variables-1

        // `brew install android-ndk` puts the NDK at /opt/homebrew/share/android-ndk which links to something like /opt/homebrew/Caskroom/android-ndk/27/AndroidNDK12077973.app/Contents/NDK
        var ndkURL = URL(fileURLWithPath: toolchainOptions.ndk ?? ProcessInfo.processInfo.environment["ANDROID_NDK_HOME"] ?? (ProcessInfo.homebrewRoot + "/share/android-ndk"))

        // if it is not there, then fallback to checking the local ANDROID_HOME location for any installed NDKs
        if !isDir(ndkURL) {
            // GH Runner ANDROID_HOME=/Users/runner/Library/Android/sdk
            let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] ?? homeDir.appendingPathComponent("Library/Android/sdk").path

            let androidNDKHome = URL(fileURLWithPath: androidHome).appendingPathComponent("ndk")
            if isDir(androidNDKHome) {
                let versions = try dirs(at: androidNDKHome).filter { dir in
                    guard let initialPart = dir.lastPathComponent.split(separator: ".").first else {
                        return false
                    }
                    guard let initialNumber = Int(initialPart.description) else {
                        return false
                    }
                    // filter out old NDK versions that won't work with the toolchain (26 or 27+ are needed)
                    return initialNumber >= 26
                }

                if let version = versions.last {
                    ndkURL = URL(fileURLWithPath: version.path)
                }
            }
        }

        if !isDir(ndkURL) {
            throw CrossCompilerError(errorDescription: "The Android NDK path could not be found. Try passing the --ndk flag or setting the ANDROID_NDK environment variable.")
        }

        let ndkPrebuilt = ndkURL.appendingPathComponent("/toolchains/llvm/prebuilt/darwin-x86_64")
        if !isDir(ndkPrebuilt) {
            throw CrossCompilerError(errorDescription: "The Android NDK prebuilt path could not be found at: \(ndkPrebuilt.path). Try passing the --ndk flag or setting the ANDROID_NDK environment variable.")
        }

        let sdk = try toolchainOptions.sdk ?? {
            let skipSDKHome = ProcessInfo.processInfo.environment["SKIP_SDK_HOME"] ?? homeDir.appendingPathComponent("Library/Developer/Skip/SDKs").path

            if !FileManager.default.fileExists(atPath: skipSDKHome) {
                throw CrossCompilerError(errorDescription: "The Skip SDKs folder does not exist: \(skipSDKHome)")
            }

            var sdks = try dirs(at: URL(fileURLWithPath: skipSDKHome))
            if let swiftVersion = toolchainOptions.swiftVersion {
                sdks = sdks.filter({ $0.lastPathComponent.hasPrefix("swift-\(swiftVersion)") })
            }

            guard let sdkPath = sdks.last else {
                throw CrossCompilerError(errorDescription: "No Swift Android SDKs matching version \(toolchainOptions.swiftVersion ?? "latest") were found in: \(skipSDKHome)")
            }

            return sdkPath.path
        }()

        if !FileManager.default.fileExists(atPath: sdk) {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK path could not be found at: \(sdk)")
        }

        let sdkURL = URL(fileURLWithPath: sdk)
        // extract the version from "swift-5.10.1-android-24-ndk-27-sdk"
        guard let sdkVersion = sdkURL.lastPathComponent.split(separator: "-").dropFirst().first?.description else {
            throw CrossCompilerError(errorDescription: "Could not extract SDK version from: \(sdkURL.path)")
        }

        // work out which toolchain to use by matching it to the Swift Android SDK
        let toolchain = try toolchainOptions.toolchain ?? {
            let toolchainOverride = ProcessInfo.processInfo.environment["SWIFT_TOOLCHAIN_DIR"].flatMap(URL.init(fileURLWithPath:))

            let toolchainsHomeGlobal = URL(fileURLWithPath: "/Library/Developer/Toolchains")
            let toolchainsHomeLocal = homeDir.appendingPathComponent("/Library/Developer/Toolchains")

            let toolchainDirs = toolchainOverride != nil ? [toolchainOverride!] : [toolchainsHomeGlobal, toolchainsHomeLocal]

            if toolchainDirs.filter({ isDir($0) }).isEmpty {
                throw CrossCompilerError(errorDescription: "The Swift toolchains folder could not be located at: \(toolchainDirs.map(\.path))")
            }

            var toolchains = try dirs(in: toolchainDirs).filter({ $0.pathExtension == "xctoolchain" })
            let swiftVersion = toolchainOptions.swiftVersion ?? sdkVersion
            toolchains = toolchains.filter({ $0.lastPathComponent.hasPrefix("swift-\(swiftVersion)") })

            guard let toolchain = toolchains.last else {
                throw CrossCompilerError(errorDescription: "No Swift Toolchain matching version \(swiftVersion) were found in: \(toolchainDirs.map(\.path))")
            }

            return toolchain.path
        }()

        let toolchainURL = URL(fileURLWithPath: toolchain)
        if !isDir(toolchainURL) {
            throw CrossCompilerError(errorDescription: "The Swift toolchain path could not be found at: \(toolchainURL.path)")
        }

        let toolchainUsrBin = toolchainURL.appendingPathComponent("usr/bin")
        if !isDir(toolchainUsrBin) {
            throw CrossCompilerError(errorDescription: "Missing required toolchain directory: \(toolchainUsrBin.path)")
        }

        let toolchainInclude = toolchainURL.appendingPathComponent("usr/lib/swift/clang/include")
        if !isDir(toolchainInclude) {
            throw CrossCompilerError(errorDescription: "Missing required toolchain directory: \(toolchainInclude.path)")
        }

        let toolsDirectory = ndkPrebuilt.appendingPathComponent("bin")
        if !isDir(toolsDirectory) {
            throw CrossCompilerError(errorDescription: "Missing required NDK directory: \(toolsDirectory.path)")
        }

        let ndkSysroot = ndkPrebuilt.appendingPathComponent("sysroot")
        if !isDir(ndkSysroot) {
            throw CrossCompilerError(errorDescription: "Missing required NDK directory: \(ndkSysroot.path)")
        }

        let sdkUsrLibSwift = sdkURL.appendingPathComponent("usr/lib/swift")
        if !isDir(sdkUsrLibSwift) {
            throw CrossCompilerError(errorDescription: "Missing required SDK directory: \(sdkUsrLibSwift.path)")
        }

        let sdkUsrLibTriple = sdkURL.appendingPathComponent("/usr/lib/" + triple)
        if !isDir(sdkUsrLibTriple) {
            throw CrossCompilerError(errorDescription: "Missing required SDK directory: \(sdkUsrLibTriple.path)")
        }

        tc.version = 1
        tc.target = target
        tc.binDir = toolchainUsrBin.path
        tc.sdk = ndkSysroot.path
        tc.extraSwiftCFlags = [
            "-tools-directory", toolsDirectory.path,
            "-resource-dir", sdkUsrLibSwift.path,
            "-L", sdkUsrLibTriple.path,
            "-I", toolchainInclude.path
        ]
        tc.extraCCFlags = [
            "-fPIC"
        ]
        tc.extraCPPFlags = [
            "-lstdc++"
        ]

        return (destination: tc, sdk: sdkURL, ndk: ndkURL, toolchain: toolchainURL)
    }

    func createToolchainDestinationJSON(for arch: AndroidArch) throws -> (destination: (destination: SerializedDestinationV1, sdk: URL, ndk: URL, toolchain: URL), url: URL) {
        let tc = try createToolchainDestination(for: arch)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        let encoded = try encoder.encode(tc.destination)
        // create a temporary destination JSON file like "aarch64-unknown-linux-android24.json"
        let tmpFile = try createTempDir().appendingPathComponent((tc.destination.target ?? "destination") + ".json")
        try encoded.write(to: tmpFile)
        return (destination: tc, url: tmpFile)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidBuildCommand: AndroidOperationCommand {
    static var configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build the native project for Android",
        shouldDisplay: true)

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Archive output folder", valueName: "directory"))
    var dir: String?

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Toolchain Options")
    var toolchainOptions: ToolchainOptions

    /// Any arguments that are not recognized are passed through to the underlying swift build command
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        try await runSwiftPM(archiveOutputFolder: dir.flatMap(URL.init(fileURLWithPath:)), with: out)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidRunCommand: AndroidOperationCommand {
    static var configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run the executable target Android device or emulator",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Cleanup temporary folders after running"))
    var cleanup: Bool = true

    @Option(help: ArgumentHelp("Remote folder on emulator/device for build upload", valueName: "path"))
    var remoteFolder: String? = nil

    @OptionGroup(title: "Toolchain Options")
    var toolchainOptions: ToolchainOptions

    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        try await runSwiftPM(cleanup: cleanup, execute: args.first, remoteFolder: remoteFolder, with: out)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidTestCommand: AndroidOperationCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Test the native project on an Android device or emulator",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Cleanup test folders after running"))
    var cleanup: Bool = true

    @Option(help: ArgumentHelp("Remote folder on emulator/device for build upload", valueName: "path"))
    var remoteFolder: String? = nil

    @OptionGroup(title: "Toolchain Options")
    var toolchainOptions: ToolchainOptions

    // TODO: how to handle test case filter/skip? It isn't an argument to `swift build`, and the _SWIFTPM_SKIP_TESTS_LIST environment variable doesn't seem to work
    //@Option(help: ArgumentHelp("Skip test cases matching regular expression", valueName: "skip"))
    //var skip: [String] = []
    //@Option(help: ArgumentHelp("Run test cases matching regular expression", valueName: "filter"))
    //var filter: [String] = []

    /// Any arguments that are not recognized are passed through to the underlying swift build command
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        try await runSwiftPM(cleanup: cleanup, remoteFolder: remoteFolder, with: out)
    }
}

struct ToolchainOptions: ParsableArguments {
    @Option(help: ArgumentHelp("Swift version to use", valueName: "v"))
    var swiftVersion: String? = nil

    @Option(help: ArgumentHelp("Swift Android SDK path", valueName: "path"))
    var sdk: String? = nil

    @Option(help: ArgumentHelp("Android NDK path", valueName: "path"))
    var ndk: String? = nil

    @Option(help: ArgumentHelp("Swift toolchain path", valueName: "path"))
    var toolchain: String? = nil

    @Option(help: ArgumentHelp("Path to the package to run", valueName: "path"))
    var packagePath: String? = nil

    @Option(help: ArgumentHelp("Custom scratch directory path", valueName: ".build"))
    var scratchPath: String? = nil

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Build with configuration", valueName: "debug"))
    var configuration: BuildConfiguration? = nil

    @Option(help: ArgumentHelp("Destination architectures"))
    var arch: [AndroidArch] = []
}

public struct CrossCompilerError : LocalizedError {
    public var errorDescription: String?
}

public struct AndroidError : LocalizedError {
    public var errorDescription: String?
}

enum AndroidArch: String, CaseIterable, ExpressibleByArgument {
    case aarch64
    case armv7
    case x86_64

    var target: String {
        switch self {
        case .aarch64:
            return "aarch64-unknown-linux-android24"
        case .armv7:
            return "armv7-unknown-linux-androideabi24"
        case .x86_64:
            return "x86_64-unknown-linux-android24"
        }
    }

    /// The name of the ABI, which is used for the folder name for the APK's embedded libraries
    var abi: String {
        switch self {
        case .aarch64:
            return "arm64-v8a"
        case .armv7:
            return "armeabi-v7a"
        case .x86_64:
            return "x86_64"
        }
    }

    var triple: String {
        switch self {
        case .aarch64:
            return "aarch64-linux-android"
        case .armv7:
            return "arm-linux-androideabi"
        case .x86_64:
            return "x86_64-linux-android"
        }
    }
}

/**
 A JSON file defining cross-compilation arguments such as:

 ```json
 {
     "version": 1,
     "target": "aarch64-unknown-linux-android24",
     "toolchain-bin-dir": "/Library/Developer/Toolchains/swift-5.10.1-RELEASE.xctoolchain/usr/bin",
     "sdk": "/Users/marc/Library/Android/sdk/ndk/27.0.12077973/toolchains/llvm/prebuilt/darwin-x86_64/sysroot",
     "extra-swiftc-flags": [
         "-tools-directory", "/Users/marc/Library/Android/sdk/ndk/27.0.12077973/toolchains/llvm/prebuilt/darwin-x86_64/bin",
         "-resource-dir", "/opt/src/github/swift-android-sdk/swift-android-sdk/swift-5.10.1-android-24-ndk-27-sdk/usr/lib/swift",
         "-L", "/opt/src/github/swift-android-sdk/swift-android-sdk/swift-5.10.1-android-24-ndk-27-sdk/usr/lib/aarch64-linux-android",
         "-I", "/Library/Developer/Toolchains/swift-5.10.1-RELEASE.xctoolchain/usr/lib/swift/clang/include"
     ],
     "extra-cc-flags": [
         "-fPIC"
     ],
     "extra-cpp-flags": [
         "-lstdc++"
     ]
 }

 Copied from:  
 https://github.com/swiftlang/swift-package-manager/blob/4ee6cd1b441bf1e766090e77a7d887c400c59732/Sources/PackageModel/SwiftSDKs/SwiftSDK.swift#L995

 ```
 */
private struct SerializedDestinationV1: Codable {
    var version: Int = 1
    var target: String?
    var sdk: String?
    var binDir: String?
    var extraCCFlags: [String] = []
    var extraSwiftCFlags: [String] = []
    var extraCPPFlags: [String] = []

    enum CodingKeys: String, CodingKey {
        case version
        case target
        case sdk
        case binDir = "toolchain-bin-dir"
        case extraCCFlags = "extra-cc-flags"
        case extraSwiftCFlags = "extra-swiftc-flags"
        case extraCPPFlags = "extra-cpp-flags"
    }
}



fileprivate extension URL {
    var homeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}

