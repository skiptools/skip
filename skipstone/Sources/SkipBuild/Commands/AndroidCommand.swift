import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ArgumentParser
import TSCBasic
import ELFKit
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
            AndroidSDKCommand.self,
            AndroidEmulatorCommand.self,
            AndroidToolchainCommand.self,
        ])
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidSDKCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sdk",
        abstract: "Manage installation of Swift Android SDK",
        shouldDisplay: androidCommandEnabled,
        subcommands: [
            AndroidSDKListCommand.self,
            AndroidSDKInstallCommand.self,
        ])
}

extension ToolchainOptionsCommand {
    /// Returns the root path to the Swift SDKs folder
    var localSDKsRootPath: URL {
        (toolchainOptions.swiftSDKHome ?? ProcessInfo.processInfo.environment["SWIFT_SDK_HOME"]).flatMap(URL.init(fileURLWithPath:)) ?? swiftPMConfigFolder.appendingPathComponent("swift-sdks", isDirectory: true)
    }

    var androidNDKDownloadRoot: URL {
        URL(string: ProcessInfo.processInfo.environment["SKIP_ANDROID_NDK_DOWNLOAD_ROOT"] ?? "https://dl.google.com/android/repository")!
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension ToolchainOptionsCommand where Self : StreamingCommand {
    func installAndroidSDK(sdkName: String = "android", version: String, ndkVersion: String, reinstall: Bool, selfTest: Bool, with out: MessageQueue) async throws {
        if version.hasPrefix("5.") || version.hasPrefix("6.0") || version.hasPrefix("6.1") || version.hasPrefix("6.2") || version.hasPrefix("nightly-6.2") {
            try await installAndroidSDKLegacy(version: version, reinstall: reinstall, with: out)
        } else {
            // something like "swift-DEVELOPMENT-SNAPSHOT-2025-12-19-a" is resolved directly

            let resolveSDKMsg = "Resolve SDK version \(version)"
            let sdks = await outputOptions.monitor(with: out, resolveSDKMsg, resultHandler: { result in
                if let sdks = try? result?.get(), let sdk = sdks.first {
                    return (result, MessageBlock(status: .pass, "\(resolveSDKMsg): \(sdk.version)"))
                } else {
                    return (result, MessageBlock(status: .fail, "\(resolveSDKMsg): none found"))
                }
            }, monitorAction: { _ in
                try await SwiftSDKOpenAPI.fetchAndroidSDKs(versionName: version)
            })

            guard let matchingSDK = try sdks.get().first else {
                throw AndroidError(errorDescription: "No Android SDK matching version \(version) could be found")
            }

            // Install the Host toolchain matching the version
            try await run(with: out, "Install Host Toolchain", ["swiftly", "install", "--assume-yes", matchingSDK.version])

            // Remove any pre-existing toolchain matching the version (permitting failure, in case it does not exist)
            let androidSDKName = matchingSDK.version + "_android"
            try await run(with: out, "Check Android SDK", ["swiftly", "run", "swift", "sdk", "remove", androidSDKName, "+\(matchingSDK.version)"], permitFailure: true)

            // Install the Android SDK
            try await run(with: out, "Install Android SDK", ["swiftly", "run", "swift", "sdk", "install", matchingSDK.downloadURL.absoluteString, "--checksum", matchingSDK.checksum, "+\(matchingSDK.version)"])

            // Install path will be like swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a_android.artifactbundle
            let artifactInstallPath = self.localSDKsRootPath.appending(component: androidSDKName).appendingPathExtension("artifactbundle")

            let swiftAndroidRoot = artifactInstallPath.appending(component: "swift-android")

            let ndkInstallScript = swiftAndroidRoot.appending(component: "scripts/setup-android-sdk.sh")
            if ndkInstallScript.isExecutableFile != true {
                throw AndroidError(errorDescription: "Android SDK setup script was not found at \(ndkInstallScript.path)")
            }

            // Download and unpack NDK
            let ndkFolder = try await downloadAndroidNDK(ndkVersion: ndkVersion, targetPath: swiftAndroidRoot, with: out)

            // Run link script for NDK
            try await run(with: out, "Link Swift Android SDK and NDK", [ndkInstallScript.path], additionalEnvironment: ["ANDROID_NDK_HOME": ndkFolder.path])

            // TODO: create example project and run Android build
        }
    }

    /// Downloads and unpacks the Android NDK to the specific directory and returns the `ANDROID_NDK_HOME` path.
    ///
    /// https://dl.google.com/android/repository/android-ndk-r27d-darwin.zip
    /// https://dl.google.com/android/repository/android-ndk-r27d-linux.zip
    func downloadAndroidNDK(ndkVersion: String, targetPath: URL, with out: MessageQueue) async throws -> URL {
        #if os(macOS)
        let ndkOS = "darwin"
        #else
        let ndkOS = "linux"
        #endif
        let ndkURL = androidNDKDownloadRoot.appending(path: "android-ndk-\(ndkVersion)-\(ndkOS).zip")

        let downloadNDKMsg = "Download NDK \(ndkVersion)"
        let (downloadPath, _) = try await outputOptions.monitor(with: out, downloadNDKMsg, resultHandler: Self.timingResultHandler(message: downloadNDKMsg, permitFailure: false)) { _ in
            try await URLSession.shared.download(from: ndkURL)
        }.get()

        try await run(with: out, "Unpack \(ndkURL.lastPathComponent)", ["unzip", "-o", "-d", targetPath.path, downloadPath.path])

        let ndkUnpackFolder = targetPath.appending(component: "android-ndk-\(ndkVersion)")
        if ndkUnpackFolder.isDirectoryFile == false {
            throw AndroidError(errorDescription: "Expected NDK unpack folder not found: \(ndkUnpackFolder.path)")
        }

        return ndkUnpackFolder
    }

    /// The older way to install the Anroid SDK, using Homebrew Casks in https://github.com/skiptools/homebrew-skip/tree/main/Casks
    func installAndroidSDKLegacy(version: String, reinstall: Bool, with out: MessageQueue) async throws {
        try await run(with: out, "Install Swift Android SDK", ["brew", reinstall ? "reinstall" : "install", "skiptools/skip/swift-android-toolchain@\(version)"], additionalEnvironment: ["HOMEBREW_AUTO_UPDATE_SECS": "0"])
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidSDKInstallCommand: MessageCommand, ToolchainOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install the native Swift Android SDK",
        usage: """
        # Installs the default version of the Android SDK
        skip android sdk install

        # Installs the latest nightly for 6.3
        skip android sdk install --version nightly-6.3
        """,
        shouldDisplay: true)

    static let defaultAndroidSDKVersion = "6.2" // TODO: 6.3
    static let defaultAndroidNDKVersion = "r27d"

    @Option(help: ArgumentHelp("Version of the Swift Android SDK to install", valueName: "version"))
    var version: String = Self.defaultAndroidSDKVersion

    @Option(help: ArgumentHelp("Version of the Android NDK to link to the toolchain", valueName: "ndk"))
    var ndkVersion: String = Self.defaultAndroidNDKVersion

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Toolchain Options")
    var toolchainOptions: ToolchainOptions

    @Flag(help: ArgumentHelp("Reinstall the Android SDK"))
    var reinstall: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Verify Android SDK installation"))
    var verify: Bool = true

    func performCommand(with out: MessageQueue) async throws {
        await withLogStream(title: "Install Swift Android SDK \(version)", with: out) {
            try await installAndroidSDK(version: version, ndkVersion: ndkVersion, reinstall: reinstall, selfTest: verify, with: out)
        }
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidSDKListCommand: SkipCommand, StreamingCommand, OutputOptionsCommand, ToolOptionsCommand {
    typealias Output = SwiftSDKOutput

    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List the installed Swift Android SDKs",
        shouldDisplay: true)

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Flag(help: ArgumentHelp("List remote SDKs that can be installed"))
    var remote: Bool = false

    @Flag(help: ArgumentHelp("Include development SDKs in remote list"))
    var devel: Bool = false

    @Option(help: ArgumentHelp("The name of the remote SDK to list", visibility: .hidden))
    var sdkName: String = "android"

    func performCommand(with out: MessageQueue) async throws {
        if remote {
            var androidSDKs = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: sdkName)
            if devel {
                // FIXME: we would need an OpenAPI endpoint to query the active develoment branches…
                for develVersion in ["6.3", "main"] {
                    if let develSDKs = try? await SwiftSDKOpenAPI.fetchSDKs(sdkName: sdkName, forDevelVersion: develVersion) {
                        androidSDKs += develSDKs
                    }
                }
            }
            for sdk in androidSDKs {
                await out.yield(SwiftSDKOutput(name: sdk.version))
            }
        } else {
            try await listAndroidSDKs(with: out)
        }
    }

    func listAndroidSDKs(with out: MessageQueue) async throws {
        let swiftSDKListOutput = try await launchTool("swift", arguments: ["sdk", "list"], includeStdErr: false)
        for try await sdkLine in swiftSDKListOutput {
            let info = SwiftSDKOutput(name: sdkLine.line)
            // handle both old ("swift-6.2-RELEASE-android-0.1.artifactbundle") and new ("swift-DEVELOPMENT-SNAPSHOT-2025-10-16-a_android.artifactbundle") patterns
            if info.name.contains("android") {
                await out.yield(info)
            }
        }
    }

    struct SwiftSDKOutput : MessageEncodable, Decodable {
        let name: String

        /// Returns the message for the output with optional ANSI coloring
        func message(term: Term) -> String? {
            name
        }
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidToolchainCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "toolchain",
        abstract: "Manage installation of Swift Android Host Toolchain",
        shouldDisplay: androidCommandEnabled,
        subcommands: [
            AndroidToolchainVersionCommand.self,
        ])
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidToolchainVersionCommand: AndroidOperationCommand {
    static var configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Show the version of the Swift Android Host Toolchain",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Toolchain Options")
    var toolchainOptions: ToolchainOptions

    var args: [String] { ["--version"] }

    func performCommand(with out: MessageQueue) async throws {
        try await runSwiftPM(defaultArch: .current, testingLibrary: nil, with: out)
    }
}

protocol ToolchainOptionsCommand : ToolOptionsCommand {
    /// This command's toolchain options
    var toolchainOptions: ToolchainOptions { get }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
protocol AndroidOperationCommand : MessageCommand, ToolchainOptionsCommand {

    /// The arguments to the command to be executed
    var args: [String] { get }
}

fileprivate extension AndroidOperationCommand {
    private func runCommand(command: [String], env: [String: String], with out: MessageQueue) async throws {
        #if !canImport(SkipDriveExternal)
        throw ToolLaunchError(errorDescription: "Cannot launch android command without SkipDriveExternal")
        #else

        if outputOptions.verbose {
            print("running command: \(env.sorted(by: { $0.key < $1.key }).map { "\($0)='\($1)'" }.joined(separator: " ")) \(command.joined(separator: " "))") // to: &TSCBasic.stderrStream) // stderrStream doesn't show up in Xcode logs
        }

        for try await outputLine in Process.streamLines(command: command, environment: env, includeStdErr: true, onExit: { result in
            guard case .terminated(0) = result.exitStatus else {
                // we failed, but did not expect an error
                throw AndroidError(errorDescription: "Error \(result.exitStatus) running command: \(command.joined(separator: " "))")
            }
        }) {
            //print(outputLine.line)

            // squelch common warnings in non-verbose output mode
            if outputLine.err {
                if !outputOptions.verbose && (
                    // additional filters to to handle warnings raised by the way we replace remote dependencies with their local equivalents
                    outputLine.line.hasSuffix(" is not used by any target") // 'swift': dependency 'swift-system' is not used by any target
                    || outputLine.line.hasSuffix("will be escalated to an error in future versions of SwiftPM.") // '…': '…' dependency on '…' conflicts with dependency on '…' which has the same identity '…'. this will be escalated to an error in future versions of SwiftPM.
                    || outputLine.line.hasSuffix("unhandled; explicitly declare them as resources or exclude from the target")
                ) {
                    continue
                }
                print(outputLine.line, to: &TSCBasic.stderrStream)
                TSCBasic.stderrStream.flush()
            } else {
                if !outputOptions.verbose && (
                    outputLine.line.hasPrefix("warning: Could not read SDKSettings.json for SDK")
                    || outputLine.line.hasPrefix("<unknown>:0: warning: glibc not found for")
                    || outputLine.line.hasPrefix("<unknown>:0: warning: libc not found for")
                ) {
                    continue
                }
                print(outputLine.line, to: &TSCBasic.stdoutStream)
                TSCBasic.stdoutStream.flush()
            }
        }
        #endif
    }

    /// Run `swift build` for the given Android architectures, optionally running the test cases on the device or copying all the files to the given `archiveOutputFolder`
    func runSwiftPM(cleanup: Bool? = nil, execute executable: String? = nil, commandEnvironment: [String] = [], defaultArch: AndroidArchArgument, remoteFolder: String? = nil, copy: [String] = [], archiveOutputFolder: URL? = nil, testingLibrary: TestingLibrary?, with out: MessageQueue) async throws {
        let buildConfig = toolchainOptions.configuration ?? BuildConfiguration.fromEnvironment() ?? .debug
        let packageDir = toolchainOptions.packagePath ?? "."
        let archs = !toolchainOptions.arch.isEmpty ? toolchainOptions.arch : [defaultArch]
        // pick the default architecture based on the current host; for running executables and tests, this will likely be the one that matches an attached emulator, but for an attached device, we don't know (e.g., an x86_64 host may be connecting to an aarch64 device).

        let architectures = archs.flatMap({ $0.architectures(configuration: buildConfig) }).uniqueElements()
        for arch in architectures {
            let tc = try buildToolchainConfiguration(for: arch)

            var env: [String: String] = ProcessInfo.processInfo.environmentWithDefaultToolPaths
            let toolchainBin = tc.toolchainPath.appendingPathComponent("usr/bin", isDirectory: true)
            let toolchainLib = tc.toolchainPath.appendingPathComponent("usr/lib", isDirectory: true)
            // when some older version of ld is earlier in the path, a user reported an error like "ld: unsupported tapi file type '!tapi-tbd' in YAML file" when trying to build; this should in theory avoid that, but there was an error where "/Users/USERNAME/anaconda3/bin/ld" was earlier in the PATH; prepending "/usr/bin/ld" to the PATH should be enough to work around this
            let path = toolchainBin.path + ":/usr/bin:" + (env["PATH"] ?? "")
            env["PATH"] = path
            // when Xcode invokes gradle which invokes `skip android build` which invokes `swift build`,
            // the inherited SDKROOT will be something like "/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator18.0.sdk",
            // which will break the build.
            // So we manually clear the SDKROOT environment variable in case it is set.
            env["SDKROOT"] = nil

            // Clear ANDROID_NDK_ROOT to work around Android cross-compilation build failures
            // https://github.com/finagolfin/swift-android-sdk/issues/207
            env["ANDROID_NDK_ROOT"] = nil

            // We also need to clear out any environment variables that may change between runs (like LLBUILD_BUILD_ID='4288622949' LLBUILD_LANE_ID='9' LLBUILD_TASK_ID='31650009000f'), since those will prevent incremental builds from happening and force a complete rebuild each time
            if env["XCODE_VERSION_MAJOR"] != nil {
                let permittedEnvironment: Set<String> = [
                    "PATH", "HOME", "HOMEBREW_PREFIX", "JAVA_HOME", "LANG", "LOGNAME", "PWD", "SHELL", "SWIFTLY_BIN_DIR", "SWIFTLY_HOME_DIR", "TMPDIR", "USER"
                ]
                env = env.filter({ (key, value) in
                    permittedEnvironment.contains(key)
                    && !key.hasPrefix("SKIP_")
                    && !key.hasPrefix("ANDROID_") // "ANDROID_HOME", "ANDROID_NDK_HOME", "ANDROID_NDK_ROOT", "ANDROID_NDK", "ANDROID_SERIAL"
                })
            }

            // manually disable the skipstone plugin from being run again in the derived build; we don't need to transpile and bridge the code a second time, we only need to build the native libraries with the Android toolchain
            //env["SKIP_PLUGIN_DISABLED"] = "1"

            let swiftCmd = toolchainBin.appendingPathComponent("swift", isDirectory: false).path
            if !FileManager.default.fileExists(atPath: swiftCmd) {
                throw CrossCompilerError(errorDescription: "Could not locate swift command at: \(swiftCmd)")
            }
            var cmd: [String] = []
            var xswiftc = toolchainOptions.xswiftc
            var xcc = toolchainOptions.xcc
            var xlinker = toolchainOptions.xlinker

            cmd += [swiftCmd]
            cmd += ["build"]

            if let destinationURL = tc.destinationURL {
                cmd += ["--destination", destinationURL.path]
            } else if let sdkName = tc.sdkName {
                cmd += ["--swift-sdk", sdkName]
            }

            let runTests = cleanup != nil && executable == nil
            if runTests {
                cmd += ["--build-tests"]
                // plugin-path is a workaround for https://github.com/swiftlang/swift-package-manager/issues/8362
                xswiftc += ["-plugin-path", toolchainLib.appendingPathComponent("swift/host/plugins/testing", isDirectory: true).path]
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

            if toolchainOptions.bridge {
                xswiftc += ["-DSKIP_BRIDGE"]
                // set the SKIP_BRIDGE flag, which is transferred through to a build #define in SkipBridge and can be used to check whether the current build mode is targetting JNI
                env["SKIP_BRIDGE"] = "1"
            }

            if toolchainOptions.aggregate {
                cmd += ["--static-swift-stdlib"]
                xswiftc += ["-L" + tc.libPathStatic.path]
                xswiftc += ["-lc++_shared"]
                xswiftc += ["-llog"]
                xswiftc += ["-Osize"]

                // enables dead stripping of unused runtime functions: swiftc -Xcc -ffunction-sections -Xcc -fdata-sections -Xcc -mthumb -Xlinker --gc-sections -Xfrontend -metadata-sections -Xfrontend -function-sections -Xfrontend -data-sections -static-stdlib -target -lswiftCore -lswiftStdlibStubsBaremetal -lstdc++_nano -lc -lg -lm -lgcc -Xlinker -T -Xlinker ./linker.ld imp.o unicode.o test.swift
                xswiftc += ["-Xfrontend", "-function-sections"]
                //xswiftc += ["-Xfrontend", "-data-sections"]
                //xswiftc += ["-Xfrontend", "-metadata-sections"]
                xcc += ["-ffunction-sections"]
                xcc += ["-fdata-sections"]
                xcc += ["-fvisibility=hidden"]
                xcc += ["-fmerge-all-constants"]

                // garbage collect unused sections
                xlinker += ["--gc-sections"]
                //xlinker += ["--print-gc-sections"] // debug removed sections
                //xlinker += ["--strip-debug"]

                // create a linker version script that excludes all global symbols other than the JNI-exported functions
                let versionScript = """
                    {
                      global:
                        Java_*;
                        JNI_*;
                      local:
                        *;
                    };

                    """

                let scratch = try toolchainOptions.scratchPath ?? createTempDir().path
                let versionScriptPath = try AbsolutePath(validating: "jni_export.map", relativeTo: AbsolutePath(validating: scratch))
                try localFileSystem.writeChanges(path: versionScriptPath, bytes: ByteString(encodingAsUTF8: versionScript))
                xlinker += ["--version-script=\(versionScriptPath.pathString)"]
                //xlinker += ["-T"]
            }

            // always set the TARGET_OS_ANDROID environment and build constant, regardless of bridging
            env["TARGET_OS_ANDROID"] = "1"
            xswiftc += ["-DTARGET_OS_ANDROID"]

            for xswiftc in xswiftc {
                cmd += ["-Xswiftc", xswiftc]
            }
            for xcc in xcc {
                cmd += ["-Xcc", xcc]
            }
            for xlinker in xlinker {
                cmd += ["-Xlinker", xlinker]
            }
            for xcxx in toolchainOptions.xcxx {
                cmd += ["-Xcxx", xcxx]
            }
            // when executable is specified, then the arguments are the command to run;
            // otherwise, they are considered build arguments
            if executable == nil {
                cmd += args
            }

            try await runCommand(command: cmd, env: env, with: out)

            let buildOutputFolder = [
                // the output folder is either the scratch path we have specified, or is the default package/.build output directory
                toolchainOptions.scratchPath ?? (packageDir + "/.build"),
                arch.tripleKey(api: toolchainOptions.androidAPILevel, sdkVersion: tc.swiftSDKVersion),
                buildConfig.rawValue,
            ].joined(separator: "/")

            let buildOutputFolderURL = URL(fileURLWithPath: buildOutputFolder)

            // we do not prune executables or tests, since we only analyze shared object dependencies and not the dependencies in executables (although we could…)
            let prune = toolchainOptions.prune == true && (executable == nil && runTests == false)

            /// Returns all the shared object files that will need to be linked to a binary
            ///
            /// e.g.: `~/Library/Developer/Skip/SDKs/swift-5.10.1-android-24-ndk-27-sdk/usr/lib/aarch64-linux-android/*.so`
            func dependencySharedObjectFiles() throws -> [URL] {
                let buildOutputLibraries: [URL] = try files(at: buildOutputFolderURL).filter({ $0.lastPathComponent.contains(".so") })

                let libFolder = tc.libPathDynamic
                if !FileManager.default.fileExists(atPath: libFolder.path) {
                    throw AndroidError(errorDescription: "Android SDK library folder did not exist at: \(libFolder)")
                }

                // filter out some of the native Android libraries that are located in the same folder as the Swift libraries
                // including these are unnecessary and also results in a hang when running test cases
                // This is only for pre-6.1 SDKs that mingle the NDK and the Swift Android SDK into a single root folder
                let builtinLibraries: Set<String> = [
                    "libandroid.so",
                    "libc.so",
                    "libm.so",
                    "libc++.so",
                    "libdl.so",
                    "liblog.so",

                    "libcamera2ndk.so",
                    "libjnigraphics.so",
                    "libmediandk.so",
                    "libvulkan.so",
                    "libEGL.so",
                    "libGLESv1_CM.so",
                    "libGLESv2.so",
                    "libGLESv3.so",
                    "libOpenMAXAL.so",
                    "libOpenSLES.so",
                ]

                // check for .so files like libswift_Concurrency.so or libxml2.so.2.13.3
                // we need to preserve symbolic links because some libraries link to a linked version
                let libraries = try files(at: libFolder, allowLinks: true)
                    .filter({ $0.lastPathComponent.contains(".so") })
                    .filter({ !builtinLibraries.contains($0.lastPathComponent) })

                let sysrootLibraries = try files(at: tc.libSysrootArch, allowLinks: true)
                    .filter({ $0.lastPathComponent.contains(".so") })

                // we always need libc++_shared.so from the NDK sysroot even if it is not an explicit dependency
                let cppShared = sysrootLibraries.filter({ $0.lastPathComponent == "libc++_shared.so" })

                if !prune {
                    // just return the unfiltered list if we are not pruning the libraries
                    return buildOutputLibraries + libraries + cppShared
                }

                // analyze the build output .so files for all their dependencies
                let dependentLibraries = try buildOutputLibraries.flatMap { try sharedObjectDependencies(for: $0, in: libraries) }
                let neededDependencies = (cppShared + dependentLibraries).uniqueElements()
                return buildOutputLibraries + neededDependencies
            }


            if let archiveOutputFolder = archiveOutputFolder {
                let archOutputFolder = archiveOutputFolder.appendingPathComponent(arch.abi, isDirectory: true)
                //try? FileManager.default.removeItem(at: archiveOutputFolder) // delete any existing archive output folder
                try FileManager.default.createDirectory(at: archOutputFolder, withIntermediateDirectories: true)

                let copyFiles = try dependencySharedObjectFiles()

                for so in copyFiles {
                    let dest = archOutputFolder.appendingPathComponent(so.lastPathComponent, isDirectory: true)
                    // TODO: we could create hardlinks rather than copying if we can check if they are on the same volume…
                    try? FileManager.default.removeItem(at: dest) // delete any pre-existing file before copy
                    try FileManager.default.copyItem(at: so, to: dest)
                }
            }

            if executable == nil && runTests == false {
                continue // nothing to do but build, so move on to the next list arch…
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
            try await run(with: out, "Connecting to Android", [adb, "shell", "mkdir", "-p", stagingDir], additionalEnvironment: env)

            // Note: one shortcoming of `adb push` is that it doesn't copy symbolic links as links, but instead pushes the underlying file; so, for example, the link libxml2.so -> libxml2.so.2.13.3 will be copied as two separate yet identical files, which increases the size of the transfer unnecessarily. In practice, this isn't a problem, since the linker will work, but it means that the directory of dependent shared objects will be bigger than it needs to be. One workaround to this might be to first archive all the files together (e.g., with tar), transfer the archive, and then unarchive them on the device, but this adds complexity to the process.
            try await run(with: out, "Copying \(runTests ? "test" : "executable") files", [adb, "push"] + transferFiles.map(\.path) + copy + [stagingDir], additionalEnvironment: env)

            var runFailure: Error?
            do {
                // in theory, we should be able to skip individual tests using the _SWIFTPM_SKIP_TESTS_LIST environment variable, but is seems to not work
                //execCommand = "_SWIFTPM_SKIP_TESTS_LIST=TestClass.testName" + " " + execCommand
                // Pre-6.1 toolchains do not support testing
                let canUseSwiftTesting = !tc.swiftSDKVersion.hasPrefix("5.") && !tc.swiftSDKVersion.hasPrefix("6.0")

                var usesSwiftTesting = testingLibrary == .testing || testingLibrary == .all
                if usesSwiftTesting {
                    // when a test contains the Swift Testing library, the tests need to be executed a second time with a special flag to activate the swift tests
                    // To determine if the shared object files contain a dependency, look at the ELFFile's needed section
                    let executableELFFile = try ELFFile(url: executablePath)
                    let executableDependencies = executableELFFile.dependencies
                    usesSwiftTesting = executableDependencies.contains("libTesting.so")
                }

                var cmd = [adb, "shell"]
                cmd += ["cd '\(stagingDir)'"]
                cmd += ["&&"]
                cmd += commandEnvironment
                cmd += ["./" + executableBase]
                if executable != nil {
                    // when not running tests, pass through the specified arguments to the command
                    cmd += args.dropFirst()
                } else if canUseSwiftTesting && usesSwiftTesting {
                    cmd += ["&&"]
                    cmd += commandEnvironment
                    cmd += ["./" + executableBase]
                    cmd += ["--testing-library", "swift-testing"]

                    // need to tack on a special check for the exit code 69, which indicates that there were no tests to run
                    // EXIT_NO_TESTS_FOUND=EX_UNAVAILABLE=69
                    // https://github.com/swiftlang/swift-testing/blob/f7705437e5010b262a10e2b3f1ce416ac18794a5/Sources/Testing/ABI/EntryPoints/SwiftPMEntryPoint.swift#L26
                    // https://github.com/skiptools/swift-android-action/commit/b4286f57fa6ab31714b86ebf9494f3748d4f520f
                    // && [ \$? -eq 0 ] || [ \$? -eq 69 ]" || true
                    cmd += ["&&", "[ $? -eq 0 ]", "||", "[ $? -eq 69 ]"]
                }
                
                try await runCommand(command: cmd, env: env, with: out)
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
        let tempURL = tmpDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        try FileManager.default.contentsOfDirectory(at: url.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
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

    func buildToolchainConfiguration(for arch: AndroidArch) throws -> ToolchainPaths {
        let apiLevel = toolchainOptions.androidAPILevel

        // look for swift-sdks like: ~/Library/org.swift.swiftpm/swift-sdks/swift-6.0.2-RELEASE-android-24-0.1.artifactbundle
        let localSDKsPath = self.localSDKsRootPath

        let installAdvice = "Install the Swift Android SDK using `skip android sdk install`."

        if !isDir(localSDKsPath) {
            throw CrossCompilerError(errorDescription: "No SDKs were installed at \(localSDKsPath.path). \(installAdvice)")
        }

        let sdks = try dirs(at: localSDKsPath)
            .filter({ $0.pathExtension == "artifactbundle" })
            .filter({ $0.lastPathComponent.hasPrefix("swift-\(toolchainOptions.swiftVersion ?? "")") && $0.lastPathComponent.contains("android") })
            // permit non-RELEASE tags if it is specified explicitly, like:
            // skip android test --swift-version 6.2-DEVELOPMENT-SNAPSHOT-2025-05-07-a
            //.filter({ toolchainOptions.swiftVersion != nil || $0.lastPathComponent.contains("RELEASE-android") })
            .sorted { u1, u2 in
                // localizedStandardCompare will handle sorting semantic versions like:
                // swift-6.1-RELEASE-android-24-0.1.artifactbundle > swift-6.0-RELEASE-android-24-0.1.artifactbundle
                // swift-6.2-DEVELOPMENT-SNAPSHOT-2025-05-07-a-android-0.1.artifactbundle > swift-6.1-RELEASE-android-24-0.1.artifactbundle
                u1.lastPathComponent.localizedStandardCompare(u2.lastPathComponent) == .orderedAscending
            }

        guard let sdkPath = sdks.last else {
            throw CrossCompilerError(errorDescription: "No Swift Android SDKs matching version \(toolchainOptions.swiftVersion ?? "latest") were found in: \(localSDKsPath.path). \(installAdvice)")
        }

        //let sdkName = sdkPath.deletingPathExtension().lastPathComponent // e.g. "swift-6.0.2-RELEASE-android-24-0.1"
        let swiftSDKVersion = sdkPath.lastPathComponent.split(separator: "-").dropFirst().first?.description ?? "latest" // e.g.: 6.0.2
        let sdkName = arch.tripleKey(api: apiLevel, sdkVersion: swiftSDKVersion)
        let infoPath = sdkPath.appendingPathComponent("info.json", isDirectory: false)
        let sdkInfo = try JSONDecoder().decode(SDKInfo.self, from: Data(contentsOf: infoPath))

        var sdkRootPath = "swift-\(swiftSDKVersion)-release-android-\(apiLevel)-sdk" // default

        let artifacts = sdkInfo.artifacts.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedDescending })
        if let defaultArtifact = artifacts.first {
            if let sdkArtifact = sdkInfo.artifacts[defaultArtifact]?.variants.first {
                sdkRootPath = sdkArtifact.path
            }
        }

        let sdkRoot = sdkPath.appendingPathComponent(sdkRootPath, isDirectory: true)
        if !isDir(sdkRoot) {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK did not exist at \(sdkRoot.path)")
        }
        let sdkJSONURL = sdkRoot.appendingPathComponent("swift-sdk.json", isDirectory: false)

        let schemaSDK = try JSONDecoder().decode(SchemaSDK.self, from: Data(contentsOf: sdkJSONURL))

        //let sysroot = try dirs(in: [sdkRoot]).first(where: { $0.lastPathComponent.hasSuffix("-sysroot") }) // e.g.: "android-27c-sysroot"
        guard let targetTriple = schemaSDK.targetTriples?[sdkName] else {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK did not contain the specified target triple: \(sdkName)")
        }
        let sysrootPath = targetTriple.sdkRootPath
        let swiftResourcesPath = targetTriple.swiftResourcesPath
        let swiftStaticResourcesPath = targetTriple.swiftStaticResourcesPath

        guard let sysrootPath else {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK did not contain an NDK sysroot at \(sdkRoot.path)")
        }

        let libSysrootBase = sdkRoot
            .appendingPathComponent(sysrootPath, isDirectory: true)
            .appendingPathComponent("usr/lib", isDirectory: true)

        let libSysrootArch = libSysrootBase
            .appendingPathComponent(arch.triple, isDirectory: true)

        if !isDir(libSysrootArch) {
            throw CrossCompilerError(errorDescription: "The Swift Android NDK library path was not found at: \(libSysrootArch.path)")
        }

        guard let swiftResourcesPath else {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK did not contain a swiftResourcesPath at \(sdkRoot.path)")
        }

        guard let swiftStaticResourcesPath else {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK did not contain a swiftStaticResourcesPath at \(sdkRoot.path)")
        }

        // folder containing the static .a files
        let libPathStatic = sdkRoot
            .appendingPathComponent(swiftStaticResourcesPath, isDirectory: true)

        if !isDir(libPathStatic) {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK static library path for \(sdkName) did not exist at: \(libPathStatic.path)")
        }

        // folder containing the shared object files
        var libPathDynamic = sdkRoot
            .appendingPathComponent(swiftResourcesPath, isDirectory: true)
            .appendingPathComponent("android", isDirectory: true)

        // pre-6.2 SDKs stored their libraries in the API-level-specific folder
        if !FileManager.default.fileExists(atPath: libPathDynamic.appendingPathComponent("libswiftCore.so", isDirectory: false).path) {
            libPathDynamic = libSysrootBase.appendingPathComponent(arch.triple, isDirectory: true)

            // pre-6.0.3 SDKs stored their libraries in the API-level-specific folder, and after in the parent folder; check each lib location for the expected "libswiftCore.so" library
            if !FileManager.default.fileExists(atPath: libPathDynamic.appendingPathComponent("libswiftCore.so", isDirectory: false).path) {
                libPathDynamic = libPathDynamic.appendingPathComponent(apiLevel.description, isDirectory: true)
                if !FileManager.default.fileExists(atPath: libPathDynamic.appendingPathComponent("libswiftCore.so", isDirectory: false).path) {
                    throw CrossCompilerError(errorDescription: "Could not locate library path for SDK: \(libPathDynamic.path)")
                }
            }
        }

        if !isDir(libPathDynamic) {
            throw CrossCompilerError(errorDescription: "The Swift Android SDK dynamic library path for \(sdkName) did not exist at: \(libPathDynamic.path)")
        }

        let toolchainPath = try swiftToolchainFolder(sdkVersion: swiftSDKVersion)
        return ToolchainPaths(toolchainPath: toolchainPath, swiftSDKVersion: swiftSDKVersion, destinationURL: nil, sdkName: sdkName, libPathDynamic: libPathDynamic, libPathStatic: libPathStatic, libSysrootArch: libSysrootArch)
    }

    func swiftToolchainFolder(sdkVersion: String) throws -> URL {
        // work out which toolchain to use by matching it to the Swift Android SDK
        let toolchain = try toolchainOptions.toolchain ?? {
            let toolchainOverride = ProcessInfo.processInfo.environment["SWIFT_TOOLCHAIN_DIR"].flatMap(URL.init(fileURLWithPath:))

            var defaultToolchains: [URL] = []
            #if os(Linux)
            // note the difference in naming between ~/.swiftpm/toolchains/swift-6.2-RELEASE-ubuntu24.04 and ~/.local/share/swiftly/toolchains/6.2.0
            defaultToolchains.append(homeDir.appendingPathComponent(".config/swiftpm/toolchains", isDirectory: true))
            defaultToolchains.append(homeDir.appendingPathComponent(".swiftpm/toolchains", isDirectory: true))
            let swiftlyToolchainDir = homeDir.appendingPathComponent(".local/share/swiftly/toolchains", isDirectory: true)
            defaultToolchains.append(swiftlyToolchainDir)
            #else
            defaultToolchains.append(URL(fileURLWithPath: "/Library/Developer/Toolchains", isDirectory: true))
            defaultToolchains.append(homeDir.appendingPathComponent("Library/Developer/Toolchains", isDirectory: true))
            #endif

            let toolchainDirs = toolchainOverride != nil ? [toolchainOverride!] : defaultToolchains.filter({ isDir($0) })

            if toolchainDirs.isEmpty {
                throw CrossCompilerError(errorDescription: "The Swift toolchains folder could not be located at: \(toolchainDirs.map(\.path))")
            }

            var toolchains = try dirs(in: toolchainDirs) // .filter({ $0.pathExtension == "xctoolchain" }) // Linux does not have an .xctoolchain suffix; maybe check the contents of the folder?
            let swiftVersion = toolchainOptions.swiftVersion ?? sdkVersion
            toolchains = toolchains.filter({ $0.lastPathComponent.hasPrefix("swift-\(swiftVersion)") })

            guard let toolchain = toolchains.last else {
                #if os(Linux)
                // On Linux, we also try to match swiftly-installed toolchains
                // ~/.local/share/swiftly/toolchains/6.2.0
                // ~/.local/share/swiftly/toolchains/main-snapshot-2025-12-19
                if isDir(swiftlyToolchainDir) {
                    let swiftlyMatch = sdkVersion.replacing("DEVELOPMENT", with: "main-snapshot")
                    let swiftlyToolchains = try dirs(in: [swiftlyToolchainDir])
                    if let swiftlyToolchain = swiftlyToolchains.filter({ $0.lastPathComponent.hasPrefix(swiftlyMatch) }).last {
                        return swiftlyToolchain.path
                    }
                }
                #endif

                throw CrossCompilerError(errorDescription: "No Swift Toolchain matching version \(swiftVersion) for SDK version \(sdkVersion) were found in: \(toolchainDirs.map(\.path))")
            }

            return toolchain.path
        }()

        let toolchainURL = URL(fileURLWithPath: toolchain)
        if !isDir(toolchainURL) {
            throw CrossCompilerError(errorDescription: "The Swift toolchain path could not be found at: \(toolchainURL.path)")
        }

        return toolchainURL
    }

    /// Returns the list of shared object file dependencies in the `needed` section of the ELF shared object file
    func sharedObjectDependencies(for url: URL, in candidates: [URL]) throws -> [URL] {
        let file = try ELFFile(url: url)
        let deps = Set(file.dependencies)
        let depURLs = candidates.filter({ deps.contains($0.lastPathComponent) })
        return try depURLs + depURLs.flatMap({ try sharedObjectDependencies(for: $0, in: candidates) })
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
        try await runSwiftPM(defaultArch: .current, archiveOutputFolder: dir.flatMap(URL.init(fileURLWithPath:)), testingLibrary: nil, with: out)
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

    @Option(help: ArgumentHelp("Environment key/value pairs for remote execution", valueName: "key=value"))
    var env: [String] = []

    @Option(help: ArgumentHelp("Additional files or folders to copy to Android", valueName: "file/folder"))
    var copy: [String] = []

    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        try await runSwiftPM(cleanup: cleanup, execute: args.first, commandEnvironment: env, defaultArch: .current, remoteFolder: remoteFolder, copy: copy, testingLibrary: nil, with: out)
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

    @Option(help: ArgumentHelp("Testing library name", valueName: "library"))
    var testingLibrary: TestingLibrary = .all

    @Option(help: ArgumentHelp("Environment key/value pairs for remote execution", valueName: "key=value"))
    var env: [String] = []

    @Option(help: ArgumentHelp("Additional files or folders to copy to Android", valueName: "file/folder"))
    var copy: [String] = []

    /// Any arguments that are not recognized are passed through to the underlying swift build command
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        try await runSwiftPM(cleanup: cleanup, commandEnvironment: env, defaultArch: .current, remoteFolder: remoteFolder, copy: copy, testingLibrary: testingLibrary, with: out)
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidEmulatorCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "emulator",
        abstract: "Manage Android emulators",
        shouldDisplay: androidCommandEnabled,
        subcommands: [
            AndroidEmulatorCreateCommand.self,
            AndroidEmulatorListCommand.self,
            AndroidEmulatorLaunchCommand.self,
        ])
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidEmulatorCreateCommand: MessageCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Install and create an Android emulator image",
        usage: """
        # Creates the default Android emulator (API 34)
        skip android emulator create

        # Creates a custom Android emulator
        skip android emulator create --name 'pixel_7_api_36' --device-profile pixel_7 --android-api-level 36 --system-image google_apis_playstore_ps16k

        # Installs a specific emulator package
        android emulator install --package 'system-images;android-31;default;arm64-v8a'
        
        """,
        discussion: """
        This command acts as a frontend to the Android SDK tools sdkmanager, avdmanager, and emulator. Run with the --verbose argument to observe the exact commands that it executes.
        """,
        shouldDisplay: true,
        aliases: ["init"])

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Option(help: ArgumentHelp("Android API emulator level", valueName: "level"))
    var androidAPILevel: Int = 34

    @Option(help: ArgumentHelp("Android emulator device profile", valueName: "profile"))
    var deviceProfile: String = "medium_phone" // "pixel_7"

    @Option(name: [.customShort("n"), .long], help: ArgumentHelp("Android emulator name", valueName: "name"))
    var name: String? = nil

    @Option(help: ArgumentHelp("The full package name of the emulator to install", valueName: "package"))
    var package: String? = nil

    @Option(help: ArgumentHelp("Android emulator APIs", valueName: "image"))
    var systemImage: String = "google_apis" // "default"

    @Option(help: ArgumentHelp("Android emulator architecture", valueName: "arch"))
    var arch: String = Self.defaultArch

    static let defaultArch: String = {
        #if arch(arm64)
        "arm64-v8a"
        #elseif arch(x86_64)
        "x86_64"
        #elseif arch(i386)
        "x86"
        #elseif arch(arm)
        "armeabi-v7a"
        #else
        fatalError("Unknown processor architecture")
        #endif
    }()

    func performCommand(with out: MessageQueue) async throws {
        func sdkmanagerInstall(_ package: String) async throws {
            try await run(with: out, "Install \(package)", ["sdkmanager", "--verbose", "--install", package])
        }

        await withLogStream(title: "Create Android emulator", with: out) {
            try await run(with: out, "Configure Android SDK Manager", ["sh", "-c", "yes | sdkmanager --licenses"])

            try await sdkmanagerInstall("platform-tools")
            try await sdkmanagerInstall("emulator")

            let emulatorSpec = self.package ?? "system-images;android-\(androidAPILevel);\(systemImage);\(arch)"

            let emulatorSpecParts = emulatorSpec.split(separator: ";")
            let androidPlatform = emulatorSpecParts.dropFirst().first ?? "android-\(androidAPILevel)"
            let actualAPILevel = androidPlatform.split(separator: "-").last.flatMap({ Int($0) }) ?? self.androidAPILevel

            try await sdkmanagerInstall("platforms;\(androidPlatform)")

            try await sdkmanagerInstall(emulatorSpec)

            var defaultName = "emulator-\(actualAPILevel)"
            //if let deviceProfile {
                defaultName += "-\(deviceProfile.lowercased().replacing(" ", with: "-"))"
            //}
            let emulatorName = name ?? defaultName

            var createCommand = ["avdmanager", "create", "avd", "--force", "-n", emulatorName, "--package", emulatorSpec]
            //if let deviceProfile {
                createCommand += ["--device", deviceProfile]
            //}

            // need to pipe through "no" to decline "Do you wish to create a custom hardware profile? [no]"
            try await run(with: out, "Create emulator: \(emulatorName)", createCommand)

            // save the emulatorName as the default for `skip android emulator launch`
            UserDefaults.standard.set(emulatorName, forKey: lastEmulatorNameDefault)
        }
    }
}

/// The UserDefaults key that remembers the last name of the emulator thay was created
private let lastEmulatorNameDefault = "skipAndroidEmulatorLaunch"


@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidEmulatorLaunchCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an Android emulator",
        usage: """
        # Launches the most recently created or used emulator
        skip android emulator launch

        # Launches an emulator with a certain name
        skip android emulator launch --name emulator-34-medium_phone

        """,
        discussion: """
        This command acts as a frontend to the Android SDK emulator command.
        Install new emulators with: skip android emulator create
        List installed emulators with: skip android emulator list
        Run with the --verbose argument to observe the exact commands that it executes.
        """,
        shouldDisplay: true,
        aliases: ["run"])

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(name: [.customShort("n"), .long], help: ArgumentHelp("Android emulator name", valueName: "name"))
    var name: String? = nil

    @Option(help: ArgumentHelp("Logcat filter (see https://developer.android.com/tools/logcat)", valueName: "filter"))
    var logcat: String = "*:D"

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Background the emulator process once it is launched"))
    var background: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Run in headless mode"))
    var headless: Bool = ProcessInfo.processInfo.environment["CI"] ?? "0" != "0"

    /// Any arguments that are not recognized are passed through to the underlying swift build command
    @Argument(parsing: .remaining, help: ArgumentHelp("Emulator arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        // ADB itself doesn't ever exit with a non-zero exit code (https://issuetracker.google.com/issues/36908392?pli=1)
        // So we need to parse the output for known error patterns and translate them into Xcode-aware messages
        #if !canImport(SkipDriveExternal)
        throw SkipDriveError(errorDescription: "SkipDrive not linked")
        #else
        var exitCode: SkipDriveExternal.ProcessResult.ExitStatus? = nil
        //~/Library/Android/sdk/emulator/emulator -avd emulator-34-pixel_7

        let emulatorName = name ?? UserDefaults.standard.string(forKey: lastEmulatorNameDefault) ?? "unknown"
        UserDefaults.standard.set(emulatorName, forKey: lastEmulatorNameDefault)

        var emulatorArgs = ["@\(emulatorName)", "-no-metrics"]
        if self.headless {
            // arguments to run without a window
            emulatorArgs += ["-no-window", "-no-boot-anim"]
        }

        if !logcat.isEmpty {
            emulatorArgs += ["-logcat", logcat]
        }

        emulatorArgs += args

        let output = try await launchTool("emulator", arguments: emulatorArgs) {
            exitCode = $0.exitStatus
        }

        for try await line in output {
            await out.write(status: nil, line.line)

            // scan for lines like:
            // INFO         | Boot completed in 23779 ms
            // INFO         | Successfully loaded snapshot 'default_boot' using 414 ms
            // 01-10 20:15:28.684     0     0 I ueventd : Coldboot took 0.096 seconds
            if self.background && (
                (line.line.hasPrefix("INFO") && line.line.contains("| Boot completed in ")) // emulator command output
                || (line.line.contains("I ueventd : Coldboot took ")) // logcat output
                ) {
                await out.write(status: .pass, "Launch complete - moving process to background (run `adb logcat` to view logs and `adb emu kill` to stop emulator)")
                break
            }
        }

        guard let exitCode = (exitCode ?? (self.background ? .terminated(code: 0) : nil)), case .terminated(0) = exitCode else {
            throw EmulatorLaunchError(errorDescription: "emulator launch error: \(String(describing: exitCode))")
        }

        #endif
    }

    public struct EmulatorLaunchError : LocalizedError {
        public var errorDescription: String?
    }
}

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidEmulatorListCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List installed Android emulators",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    func performCommand(with out: MessageQueue) async throws {
        try await listAndroidEmulators(with: out)
    }

    func listAndroidEmulators(with out: MessageQueue) async throws {
        //~/Library/Android/sdk/emulator/emulator -list-avds

        #if canImport(SkipDriveExternal)
        var exitCode: SkipDriveExternal.ProcessResult.ExitStatus? = nil
        let output = try await launchTool("emulator", arguments: ["-list-avds"]) {
            exitCode = $0.exitStatus
        }

        for try await line in output {
            await out.write(status: nil, line.line)
        }

        guard let exitCode = exitCode, case .terminated(0) = exitCode else {
            throw EmulatorListError(errorDescription: "Error listing active emulators: \(String(describing: exitCode))")
        }
        #else
        throw EmulatorListError(errorDescription: "Error listing active emulators: SkipDriveExternal not available")
        #endif
    }

    public struct EmulatorListError : LocalizedError {
        public var errorDescription: String?
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

    // Ideally, -Xswiftc, -Xcc, -Xlinker, and -Xcxx would be handled by the `@Argument(parsing: .allUnrecognized)` attribute of args, but the single dash seems to confuse it…

    @Option(name: [.customLong("Xswiftc", withSingleDash: true)], parsing: .unconditionalSingleValue, help: ArgumentHelp("Pass flag through to all Swift compiler invocations"))
    var xswiftc: [String] = []

    @Option(name: [.customLong("Xcc", withSingleDash: true)], parsing: .unconditionalSingleValue, help: ArgumentHelp("Pass flag through to all C compiler invocations"))
    var xcc: [String] = []

    @Option(name: [.customLong("Xlinker", withSingleDash: true)], parsing: .unconditionalSingleValue, help: ArgumentHelp("Pass flag through to all linker invocations"))
    var xlinker: [String] = []

    @Option(name: [.customLong("Xcxx", withSingleDash: true)], parsing: .unconditionalSingleValue, help: ArgumentHelp("Pass flag through to all C++ compiler invocations"))
    var xcxx: [String] = []

    @Option(name: [.customShort("c"), .long], help: ArgumentHelp("Build with configuration", valueName: "debug"))
    var configuration: BuildConfiguration? = nil

    @Option(help: ArgumentHelp("Destination architectures"))
    var arch: [AndroidArchArgument] = []

    @Option(help: ArgumentHelp("Android API level", valueName: "level"))
    var androidAPILevel: Int = 28

    @Option(help: ArgumentHelp("Root path for Swift SDK", valueName: "path"))
    var swiftSDKHome: String? = nil

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Enable SKIP_BRIDGE bridging to Kotlin"))
    var bridge: Bool = true

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Enable bundling all libraries into a single shared object"))
    var aggregate: Bool = (ProcessInfo.processInfo.environment["SKIP_AGGREGATE"] ?? "0") != "0"

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Prune non-dependent libraries from build output"))
    var prune: Bool = true
}

public struct CrossCompilerError : LocalizedError {
    public var errorDescription: String?
}

public struct AndroidError : LocalizedError {
    public var errorDescription: String?
}

struct ToolchainPaths {
    let toolchainPath: URL
    let swiftSDKVersion: String
    let destinationURL: URL?
    let sdkName: String?
    let libPathDynamic: URL
    let libPathStatic: URL
    let libSysrootArch: URL
}

/// The library for `swift test`
enum TestingLibrary: String, ExpressibleByArgument {
    /// Try to use both Testing and XCTest
    case all
    /// Test only with the Testling library
    case testing
    /// Test only with the XCTest library
    case xctest
}


enum AndroidArchArgument: String, ExpressibleByArgument, CaseIterable {
    /// When `ONLY_ACTIVE_ARCH` is set, uses `current` otherwise uses the default supported architectures
    case automatic
    /// The host architecture, which is suitable for running on the current machine
    case current
    case `default`
    case all
    case aarch64
    case armv7
    case x86_64

    static let exportArchsEnvironment = "SKIP_EXPORT_ARCHS"

    func architectures(configuration: BuildConfiguration) -> [AndroidArch] {
        switch self {
        case .automatic:
            // For debug builds, just build for the current architecture.
            // Ideally we would use `ONLY_ACTIVE_ARCH`, but that seems to be always set to "YES" even for Release builds.
            // The "SKIP_EXPORT_ARCHS" is used to pass the flags from `skip export --arch …` through the gradle process, which always exports with "automatic"
            if let archList = ProcessInfo.processInfo.environment[Self.exportArchsEnvironment], !archList.isEmpty {
                return archList.split(separator: ",").compactMap(String.init).compactMap(AndroidArch.init)
            } else if configuration == .release {
                return AndroidArchArgument.`default`.architectures(configuration: configuration)
            } else {
                return AndroidArchArgument.current.architectures(configuration: configuration)
            }
        case .current:
            return ProcessInfo.isARM ? [.aarch64] : [.x86_64]
        case .default:
            return [.aarch64, .x86_64, .armv7]
        case .all:
            return [.aarch64, .x86_64, .armv7]
        case .aarch64:
            return [.aarch64]
        case .armv7:
            return [.armv7]
        case .x86_64:
            return [.x86_64]
        }

    }
}

enum AndroidArch: String {
    case aarch64
    case armv7
    case x86_64

    /// The key in the `swift-sdk.json` file as decoded by `SchemaSDK`
    func tripleKey(api: Int, sdkVersion: String) -> String {
        switch self {
        case .aarch64:
            return "aarch64-unknown-linux-android\(api)"
        case .armv7:
            // older SDKs set the tripe name like armv7-unknown-linux-androideabi28, newer are just armv7-unknown-linux-android28
            return sdkVersion.hasPrefix("5") || sdkVersion.hasPrefix("6.0") || sdkVersion.hasPrefix("6.1") ? "armv7-unknown-linux-androideabi\(api)" : "armv7-unknown-linux-android\(api)"
        case .x86_64:
            return "x86_64-unknown-linux-android\(api)"
        }
    }

    /// e.g.: `~/Library/org.swift.swiftpm/swift-sdks/swift-6.1-RELEASE-android-24-0.1.artifactbundle/swift-6.1-release-android-24-sdk/android-27c-sysroot/usr/lib/arm-linux-androideabi`
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

    var libpathDynamic: String {
        switch self {
        case .aarch64:
            return "aarch64-linux-android"
        case .armv7:
            return "armv7-linux-androideabi" // note: different from triple, which is: "arm-linux-androideabi"
        case .x86_64:
            return "x86_64-linux-android"
        }
    }

    /// e.g. `~/Library/org.swift.swiftpm/swift-sdks/swift-6.0.3-RELEASE-android-24-0.1.artifactbundle/swift-6.0.3-release-android-24-sdk/android-27c-sysroot/usr/lib/swift_static-x86_64`
    var libpathStatic: String {
        switch self {
        case .aarch64:
            return "swift_static-aarch64"
        case .armv7:
            return "swift_static-armv7"
        case .x86_64:
            return "swift_static-x86_64"
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

}

/**
 ```
 {
     "schemaVersion": "1.0",
     "artifacts": {
         "swift-6.0.3-RELEASE-android-24-0.1": {
             "variants": [ { "path": "swift-6.0.3-release-android-24-sdk" } ],
             "version": "0.1",
             "type": "swiftSDK"
         }
     }
 }
 ```

 or:

 ```
 {
   "schemaVersion": "1.0",
   "artifacts": {
     "swift-6.2-DEVELOPMENT-SNAPSHOT-2025-04-24-a-android-0.1": {
       "variants": [
         {
           "path": "swift-android"
         }
       ],
       "version": "0.1",
       "type": "swiftSDK"
     }
   }
 }
 ```
 */
struct SDKInfo: Decodable {
    let schemaVersion: String
    var artifacts: [String: SDKInfoArtifact]

    struct SDKInfoArtifact: Decodable {
        let variants: [SDKVariant]
        let version: String // "0.1"
        let type: String // "swiftSDK"

        struct SDKVariant: Decodable {
            let path: String
        }
    }
}

/**
 ```
 {
     "schemaVersion": "4.0",
     "targetTriples": {
         "aarch64-unknown-linux-android24": {
             "sdkRootPath": "android-27c-sysroot",
             "swiftResourcesPath": "android-27c-sysroot/usr/lib/swift",
             "swiftStaticResourcesPath": "android-27c-sysroot/usr/lib/swift_static-aarch64"
         },
         "x86_64-unknown-linux-android24": {
             "sdkRootPath": "android-27c-sysroot",
             "swiftResourcesPath": "android-27c-sysroot/usr/lib/swift",
             "swiftStaticResourcesPath": "android-27c-sysroot/usr/lib/swift_static-x86_64"
         },
         "armv7-unknown-linux-androideabi24": {
             "sdkRootPath": "android-27c-sysroot",
             "swiftResourcesPath": "android-27c-sysroot/usr/lib/swift",
             "swiftStaticResourcesPath": "android-27c-sysroot/usr/lib/swift_static-armv7"
         }
     }
 }
 ```
 */
struct SchemaSDK: Decodable {
    let schemaVersion: String
    let targetTriples: [String: SchemaTargetTriple]?

    struct SchemaTargetTriple: Decodable {
        let sdkRootPath: String?
        let swiftResourcesPath: String?
        let swiftStaticResourcesPath: String?
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

struct SwiftSDKOpenAPI {
    static let endpointRoot = URL(string: ProcessInfo.processInfo.environment["SKIP_SWIFT_API_ENDPOINT_ROOT"] ?? "https://www.swift.org/api/v1")!
    static let downloadEndpointRoot = URL(string: ProcessInfo.processInfo.environment["SKIP_SWIFT_API_DOWNLOAD_ROOT"] ?? "https://download.swift.org")!

    /// e.g., https://www.swift.org/api/v1/install/releases.json
    static let releasesEndpoint = endpointRoot.appending(components: "install", "releases.json")

    /// e.g., https://www.swift.org/api/v1/install/dev/6.3/android-sdk.json
    static func devSnapshotEndpoint(sdkName: String, forVersion version: String) -> URL {
        endpointRoot.appending(components: "install", "dev", version, sdkName + "-sdk.json")
    }

    static func fetchAndroidSDKs(sdkName: String = "android", versionName toolchainVersion: String) async throws -> [SwiftSDKDownloadable] {
        let sdks: [SwiftSDKDownloadable]
        if toolchainVersion.hasPrefix("nightly-") {
            let develVersion = toolchainVersion.split(separator: "-").last?.description ?? toolchainVersion
            do {
                sdks = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: sdkName, forDevelVersion: develVersion)
            } catch let error as URLResponse.HTTPURLResponseError {
                if error.code == 404 {
                    throw AndroidError(errorDescription: "No Android SDK for version \(toolchainVersion) is available: \(error.localizedDescription)")
                } else {
                    throw error
                }
            }
        } else if toolchainVersion.contains("-DEVELOPMENT-SNAPSHOT-") {
            // snapshots are explicit references to individual builds:
            // e.g., swift-DEVELOPMENT-SNAPSHOT-2025-12-19-a
            // e.g., swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a
            // we still need to grab it from the API, since it contains the checksum and exact download URL
            let develVersion = toolchainVersion.hasPrefix("swift-DEVELOPMENT-SNAPSHOT-") ? "main" : toolchainVersion.split(separator: "-").dropFirst().first?.description ?? toolchainVersion
            sdks = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: sdkName, forDevelVersion: develVersion)
                .filter({ $0.version == toolchainVersion })
        } else {
            // expects a release like 6.3.1
            sdks = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: sdkName)
                .filter({ $0.version == toolchainVersion })
        }

        return sdks
    }

    static func fetchSDKs(sdkName: String, forDevelVersion develVersion: String? = nil, retryCount: Int = 5) async throws -> [SwiftSDKDownloadable] {
        let sdkPlatform = "\(sdkName)-sdk"
        if let develVersion = develVersion {
            let swiftBranch = develVersion == "main" ? "development" : "swift-\(develVersion)-branch"

            let develSDKs = try await Array<DevelSDK>(fromJSON: URLSession.shared.fetch(request: URLRequest(url: Self.devSnapshotEndpoint(sdkName: sdkName, forVersion: develVersion)), retryCount: retryCount).0, dateDecodingStrategy: .iso8601)
            return develSDKs.map { develSDK in
                // e.g.: https://download.swift.org/development/android-sdk/swift-DEVELOPMENT-SNAPSHOT-2025-12-17-a/swift-DEVELOPMENT-SNAPSHOT-2025-12-17-a_android.artifactbundle.tar.gz
                // e.g.: https://download.swift.org/swift-6.2-branch/wasm-sdk/swift-6.2-DEVELOPMENT-SNAPSHOT-2025-12-03-a/swift-6.2-DEVELOPMENT-SNAPSHOT-2025-12-03-a_wasm.artifactbundle.tar.gz
                let downloadURL = downloadEndpointRoot.appending(components: swiftBranch, sdkPlatform, develSDK.dir, develSDK.download)
                // the "dir" property is the closest thing we have to a unique version name (e.g., "swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a")
                return SwiftSDKDownloadable(version: develSDK.dir, name: develSDK.name, checksum: develSDK.checksum, downloadURL: downloadURL)
            }
        } else {
            let releases = try await Array<SwiftReleases>(fromJSON: URLSession.shared.fetch(request: URLRequest(url: Self.releasesEndpoint), retryCount: retryCount).0, dateDecodingStrategy: .iso8601)
            return releases.compactMap { release in
                guard let sdk = release.platforms.first(where: { $0.platform == sdkPlatform}) else {
                    return nil
                }
                guard let checksum = sdk.checksum else {
                    return nil
                }
                // now create a SDKAPI from the release and SDK:
                // e.g.: https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz
                // e.g.: https://download.swift.org/swift-6.2.3-release/wasm-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_wasm.artifactbundle.tar.gz
                // unlike the development endpoints which have a useful "dir" and "download" property, we have to guess based on convention
                let sdkPath = sdkName == "static" ? "static-linux-0.0.1" : sdkName // special-case legacy static linux name
                let downloadPath = "\(release.tag)_\(sdkPath).artifactbundle.tar.gz"
                let downloadURL = downloadEndpointRoot.appending(components: release.tag.lowercased(), sdkPlatform, release.tag, downloadPath)
                return SwiftSDKDownloadable(version: release.name, name: sdk.name, checksum: checksum, downloadURL: downloadURL)
            }
        }
    }

    /// A location for a particular Swift SDK
    struct SwiftSDKDownloadable: Equatable {
        var version: String // 6.2.3, swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a
        var name: String // Static SDK
        var checksum: String // f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c
        var downloadURL: URL
    }

    private struct SwiftReleases: Decodable {
        var name: String // 6.2.3
        var tag: String // swift-6.2.3-RELEASE
        var date: String? // 2025-12-12
        var xcode: String? // Xcode 26.2
        var xcode_release: Bool?
        var xcode_toolchain: Bool?

        var platforms: [SwiftReleasePlatform]

        struct SwiftReleasePlatform: Decodable {
            var name: String // Static SDK
            var platform: String // static-sdk
            var checksum: String? // f30ec724d824ef43b5546e02ca06a8682dafab4b26a99fbb0e858c347e507a2c
            var archs: [String]? // ["x86_64","arm64"]
        }
    }

    private struct DevelSDK: Decodable {
        var name: String // Swift Android SDK Development Snapshot
        var dir: String // swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a
        var download: String // swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a_android.artifactbundle.tar.gz
        var download_signature: String? // swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a_android.artifactbundle.tar.gz.sig
        var date: String // 2025-12-18 10:10:00 -0600 (note: not a proper ISO-8601 timestamp, so cannot use Date)
        var checksum: String // 0e6d657377dd1b67c5f779a72a3234ce06b8fb3ba63d1b122197e0df5f0966b4
    }
}

fileprivate extension URL {
    var homeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }
}

extension Collection where Element: Hashable {
    /// Returns a new list of element removing duplicate elements.
    ///
    /// Note: The order of elements is preseved.
    /// Complexity: O(n)
    func uniqueElements() -> [Element] {
        var set = Set<Element>()
        var result = [Element]()
        for element in self {
            if set.insert(element).inserted {
                result.append(element)
            }
        }
        return result
    }
}
