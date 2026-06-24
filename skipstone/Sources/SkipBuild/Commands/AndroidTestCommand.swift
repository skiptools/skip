// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import TSCBasic
import ELFKit
#if canImport(SkipDriveExternal)
import SkipDriveExternal
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct AndroidTestCommand: AndroidOperationCommand {
    static var configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Test the native project on an Android device or emulator",
        usage: """
        # Run tests on a connected device/emulator
        skip android test

        # Run tests packaged as an APK (instrumented tests)
        skip android test --apk

        # Target a specific emulator
        skip android test --android-serial emulator-5554

        # Run only Swift Testing tests
        skip android test --testing-library testing
        """,
        discussion: """
        Builds Swift tests for Android, pushes them to a device or emulator, and executes them. \
        By default, tests run as a native executable via adb shell. With --apk, tests are \
        packaged as an Android APK and run via instrumentation, which is required for tests \
        that need an Android application context.
        """,
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Android Runtime Options")
    var androidRuntimeOptions: AndroidRuntimeOptions

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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Package and run tests as an Android APK"))
    var apk: Bool = false

    @Option(help: ArgumentHelp("Build the native Swift Testing bundle + JNI harness into <dir>/<abi> (jniLibs layout) instead of running them; used by the Gradle connectedAndroidTest path for `mode: native` test modules", valueName: "dir"))
    var buildTestLibs: String? = nil

    @Flag(help: ArgumentHelp("With --build-test-libs, build the test bundle + harness for the HOST (Robolectric / `testDebug`, no device) instead of Android"))
    var robolectric: Bool = false

    @Option(help: ArgumentHelp("Path to write the JSON event stream output", valueName: "path"))
    var eventStreamOutputPath: String? = nil

    /// Any arguments that are not recognized are passed through to the underlying swift build command
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        if let buildTestLibs = buildTestLibs {
            if robolectric {
                try await buildLocalTestLibs(outputDir: buildTestLibs, with: out)
            } else {
                try await buildNativeTestLibs(outputDir: buildTestLibs, with: out)
            }
        } else if apk {
            try await runSwiftPMAsAPK(cleanup: cleanup, eventStreamOutputPath: eventStreamOutputPath, with: out)
        } else {
            try await runSwiftPM(cleanup: cleanup, commandEnvironment: env, defaultArch: .current, remoteFolder: remoteFolder, copy: copy, testingLibrary: testingLibrary, with: out)
        }
    }
}

fileprivate extension AndroidOperationCommand {

    /// Resolve Android SDK build tool paths for the given API level
    func resolveAndroidSDKBuildTools(androidAPILevel: Int) throws -> AndroidBuildTools {
        guard let androidHome = ProcessInfo.androidHome else {
            throw AndroidError(errorDescription: "ANDROID_HOME is not set and the default Android SDK location was not found. Set ANDROID_HOME or install the Android SDK.")
        }

        let buildToolsDir = URL(fileURLWithPath: androidHome).appendingPathComponent("build-tools", isDirectory: true)
        guard isDir(buildToolsDir) else {
            throw AndroidError(errorDescription: "Android SDK build-tools directory not found at: \(buildToolsDir.path)")
        }

        // find the latest build-tools version
        let versions = try dirs(at: buildToolsDir).sorted { u1, u2 in
            u1.lastPathComponent.localizedStandardCompare(u2.lastPathComponent) == .orderedAscending
        }
        guard let latestVersion = versions.last else {
            throw AndroidError(errorDescription: "No build-tools versions found in: \(buildToolsDir.path)")
        }

        let aapt2 = latestVersion.appendingPathComponent("aapt2", isDirectory: false).path
        let d8 = latestVersion.appendingPathComponent("d8", isDirectory: false).path
        let zipalign = latestVersion.appendingPathComponent("zipalign", isDirectory: false).path
        let apksigner = latestVersion.appendingPathComponent("apksigner", isDirectory: false).path

        for (name, path) in [("aapt2", aapt2), ("d8", d8), ("zipalign", zipalign), ("apksigner", apksigner)] {
            if !FileManager.default.isExecutableFile(atPath: path) {
                throw AndroidError(errorDescription: "Android SDK tool '\(name)' not found at: \(path)")
            }
        }

        // find android.jar for the target API level
        let platformsDir = URL(fileURLWithPath: androidHome).appendingPathComponent("platforms", isDirectory: true)
        let apiDir = platformsDir.appendingPathComponent("android-\(androidAPILevel)", isDirectory: true)
        var androidJar = apiDir.appendingPathComponent("android.jar", isDirectory: false).path

        if !FileManager.default.fileExists(atPath: androidJar) {
            // fall back to the highest available platform
            if let latest = try? dirs(at: platformsDir).filter({ $0.lastPathComponent.hasPrefix("android-") }).sorted(by: { u1, u2 in
                u1.lastPathComponent.localizedStandardCompare(u2.lastPathComponent) == .orderedAscending
            }).last {
                let fallback = latest.appendingPathComponent("android.jar", isDirectory: false).path
                if FileManager.default.fileExists(atPath: fallback) {
                    androidJar = fallback
                } else {
                    throw AndroidError(errorDescription: "android.jar not found for API level \(androidAPILevel) at: \(apiDir.path)")
                }
            } else {
                throw AndroidError(errorDescription: "android.jar not found for API level \(androidAPILevel) at: \(apiDir.path)")
            }
        }

        return AndroidBuildTools(aapt2: aapt2, d8: d8, zipalign: zipalign, apksigner: apksigner, androidJar: androidJar)
    }

    /// Generate an AndroidManifest.xml for the instrumentation test APK
    func generateTestManifest(packageName: String, androidAPILevel: Int) -> String {
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                package="\(packageName)">
                <application android:hasCode="true" android:label="SwiftTest" />
                <instrumentation
                    android:name="\(testFullClass)"
                    android:targetPackage="\(packageName)" />
                <uses-sdk android:minSdkVersion="\(androidAPILevel)" android:targetSdkVersion="\(androidAPILevel)" />
            </manifest>
            """
    }

    func signAPK(_ env: [String : String], _ out: MessageQueue, _ buildTools: AndroidBuildTools, _ sourceAPK: URL) async throws -> URL {
        // Create debug keystore
        let debugKeystorePath = (NSHomeDirectory() as NSString).appendingPathComponent(".android/debug.keystore")
        if !FileManager.default.fileExists(atPath: debugKeystorePath) {
            let androidDir = (NSHomeDirectory() as NSString).appendingPathComponent(".android")
            try FileManager.default.createDirectory(atPath: androidDir, withIntermediateDirectories: true)
            try await runCommand(command: [
                "keytool", "-genkeypair",
                "-keystore", debugKeystorePath,
                "-storepass", "android",
                "-alias", "androiddebugkey",
                "-keypass", "android",
                "-keyalg", "RSA",
                "-keysize", "2048",
                "-validity", "10000",
                "-dname", "CN=Android Debug,O=Android,C=US",
            ], env: env, with: out)
        }

        let signedAPK = sourceAPK.appendingToLastPathComponent("-signed") // app.apk -> app-signed.apk

        // apksigner sign
        try await runCommand(command: [
            buildTools.apksigner, "sign",
            "--ks", debugKeystorePath,
            "--ks-pass", "pass:android",
            "--ks-key-alias", "androiddebugkey",
            "--key-pass", "pass:android",
            "--out", signedAPK.path,
            sourceAPK.path,
        ], env: env, with: out)

        return signedAPK
    }

    /// Build the native Swift Testing bundle + the Android JNI harness (`libtest_harness.so`) into
    /// `<outputDir>/<abi>` (jniLibs layout) for the Gradle `connectedAndroidTest` path. The on-device
    /// `org.swift.test.SwiftTestRunner` then `System.loadLibrary("test_harness")` and runs swt.
    func buildNativeTestLibs(outputDir: String, with out: MessageQueue) async throws {
        #if !canImport(SkipDriveExternal)
        throw ToolLaunchError(errorDescription: "Cannot launch android command without SkipDriveExternal")
        #else
        try await stageTestLibs(try await androidTestLibsTarget(with: out), outputDir: outputDir, with: out)
        #endif
    }

    /// Build the native Swift Testing bundle + a pure-Swift host JNI harness (`libtest_harness.dylib`)
    /// into `<outputDir>` (plus a `dyld-env.txt`) for the Robolectric (`testDebug`, no device) path. The
    /// host `org.swift.test.SwiftTestRunner` then `System.load`s the harness and runs swt.
    func buildLocalTestLibs(outputDir: String, with out: MessageQueue) async throws {
        #if !canImport(SkipDriveExternal)
        throw ToolLaunchError(errorDescription: "Cannot launch android command without SkipDriveExternal")
        #else
        try await stageTestLibs(try await hostTestLibsTarget(with: out), outputDir: outputDir, with: out)
        #endif
    }

    /// Build Swift tests as a shared library, package into an APK with an Instrumentation runner,
    /// install, launch via `am instrument`, and stream structured test output.
    /// Uses `swt_abiv0_getEntryPoint` for Swift Testing integration.
    func runSwiftPMAsAPK(cleanup: Bool, eventStreamOutputPath: String?, with out: MessageQueue) async throws {
        #if !canImport(SkipDriveExternal)
        throw ToolLaunchError(errorDescription: "Cannot launch android command without SkipDriveExternal")
        #else
        let buildConfig = toolchainOptions.configuration ?? BuildConfiguration.fromEnvironment() ?? .debug
        let packageDir = toolchainOptions.packagePath ?? "."
        let archs = !toolchainOptions.arch.isEmpty ? toolchainOptions.arch : [AndroidArchArgument.current]
        let architectures = archs.flatMap({ $0.architectures(configuration: buildConfig) }).uniqueElements()

        // APK mode only supports a single architecture
        guard let arch = architectures.first else {
            throw AndroidError(errorDescription: "No target architecture specified")
        }

        let apiLevel = toolchainOptions.androidAPILevel
        let tc = try buildToolchainConfiguration(for: arch)
        let toolchainBin = tc.toolchainPath.appendingPathComponent("usr/bin", isDirectory: true)
        let swiftCmd = toolchainBin.appendingPathComponent("swift", isDirectory: false).path

        var (_, env, binPath) = try await runToolchainCommand(tc, executable: nil, testMode: .sharedObject, with: out)

        // Resolve the target Android device/emulator for adb commands
        if let serial = try await resolveAndroidSerial(with: out) {
            env["ANDROID_SERIAL"] = serial
        }

        let buildOutputFolder: String
        if let binPath = binPath, !binPath.isEmpty {
            buildOutputFolder = binPath
        } else {
            buildOutputFolder = [
                toolchainOptions.scratchPath ?? (packageDir + "/.build"),
                arch.tripleKey(api: apiLevel, sdkVersion: tc.swiftSDKVersion),
                buildConfig.rawValue,
            ].joined(separator: "/")
        }
        let buildOutputFolderURL = URL(fileURLWithPath: buildOutputFolder)

        let packageManifest = try await parseSwiftPackage(with: out, at: packageDir, swift: swiftCmd)
        let packageName = packageManifest.name

        // Discover the test library: native uses .xctest, swiftbuild uses .so
        let xctestName = packageName + "PackageTests.xctest"
        let xctestPath = buildOutputFolderURL.appendingPathComponent(xctestName)
        let testLibName: String
        let testLibPath: URL

        if FileManager.default.fileExists(atPath: xctestPath.path) {
            testLibName = xctestName
            testLibPath = xctestPath
        } else {
            // swiftbuild: look for {Module}Tests.so
            let testTargets = packageManifest.targets.compactMap(\.a).filter({ $0.type == "test" }).map(\.name)
            var foundLib: String? = nil
            for targetName in testTargets {
                let soName = targetName + ".so"
                let soPath = buildOutputFolderURL.appendingPathComponent(soName)
                if FileManager.default.fileExists(atPath: soPath.path) {
                    foundLib = soName
                    break
                }
            }
            if let lib = foundLib {
                testLibName = lib
                testLibPath = buildOutputFolderURL.appendingPathComponent(lib)
            } else {
                throw AndroidError(errorDescription: "Could not find test library in: \(buildOutputFolderURL.path). Expected \(xctestName) (native) or a *Tests.so file (swiftbuild)")
            }
        }

        if !FileManager.default.fileExists(atPath: testLibPath.path) {
            throw AndroidError(errorDescription: "Expected test library did not exist at: \(testLibPath.path)")
        }

        // --- Collect shared object dependencies ---
        let buildOutputLibraries: [URL] = try files(at: buildOutputFolderURL).filter({ $0.lastPathComponent.contains(".so") })
        let libFolder = tc.libPathDynamic
        if !FileManager.default.fileExists(atPath: libFolder.path) {
            throw AndroidError(errorDescription: "Android SDK library folder did not exist at: \(libFolder)")
        }

        let libraries = try files(at: libFolder, allowLinks: true)
            .filter({ $0.lastPathComponent.contains(".so") })
            .filter({ !builtinLibraries.contains($0.lastPathComponent) })

        let sysrootLibraries = try files(at: tc.libSysrootArch, allowLinks: true)
            .filter({ $0.lastPathComponent.contains(".so") })
        let cppShared = sysrootLibraries.filter({ $0.lastPathComponent == "libc++_shared.so" })

        let allSharedObjects = buildOutputLibraries + libraries + cppShared

        // --- Resolve Android SDK build tools ---
        let buildTools = try resolveAndroidSDKBuildTools(androidAPILevel: apiLevel)

        // --- Create temp staging directory ---
        let stagingDir = try createTempDir()
        defer {
            if cleanup {
                try? FileManager.default.removeItem(at: stagingDir)
            }
        }

        let apkContentDir = stagingDir.appendingPathComponent("apk-content", isDirectory: true)
        let libDir = apkContentDir.appendingPathComponent("lib/\(arch.abi)", isDirectory: true)
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)

        // Copy test .so and all dependency .so files into lib/{abi}/
        let testLibDest = libDir.appendingPathComponent("lib\(packageName)Test.so", isDirectory: false)
        try FileManager.default.copyItem(at: testLibPath, to: testLibDest)

        for so in allSharedObjects {
            let dest = libDir.appendingPathComponent(so.lastPathComponent, isDirectory: false)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: so, to: dest)
        }

        // --- Build Swift test harness ---
        let harnessDir = stagingDir.appendingPathComponent("harness", isDirectory: true)

        // Create package directory structure:
        //   harness/Package.swift
        //   harness/Sources/TestHarness/TestRunner.swift
        let testHarnessSourceDir = harnessDir.appendingPathComponent("Sources/TestHarness", isDirectory: true)
        try FileManager.default.createDirectory(at: testHarnessSourceDir, withIntermediateDirectories: true)

        try harnessPackageSwift.write(to: harnessDir.appendingPathComponent("Package.swift", isDirectory: false), atomically: true, encoding: .utf8)
        try testHarnessSwiftSource(testLibName: "lib\(packageName)Test.so").write(to: testHarnessSourceDir.appendingPathComponent("TestRunner.swift", isDirectory: false), atomically: true, encoding: .utf8)

        // Build the harness package for Android
        var harnessCmd: [String] = [swiftCmd, "build"]
        if let sdkName = tc.sdkName {
            harnessCmd += ["--swift-sdk", sdkName]
        }
        harnessCmd += ["--package-path", harnessDir.path, "--configuration", buildConfig.rawValue]
        if outputOptions.verbose {
            harnessCmd += ["--verbose"]
        }
        // Forward --build-system if specified
        if let bsIdx = args.firstIndex(of: "--build-system"), bsIdx + 1 < args.count {
            harnessCmd += ["--build-system", args[bsIdx + 1]]
        }
        try await runCommand(command: harnessCmd, env: env, with: out)

        // Locate the built .so using --show-bin-path
        var harnessBinPathCmd: [String] = [swiftCmd, "build", "--show-bin-path"]
        if let sdkName = tc.sdkName {
            harnessBinPathCmd += ["--swift-sdk", sdkName]
        }
        harnessBinPathCmd += ["--package-path", harnessDir.path, "--configuration", buildConfig.rawValue]
        if let bsIdx = args.firstIndex(of: "--build-system"), bsIdx + 1 < args.count {
            harnessBinPathCmd += ["--build-system", args[bsIdx + 1]]
        }

        var harnessBuildOutput: String
        if let stream = try? await launchTool(swiftCmd, arguments: Array(harnessBinPathCmd.dropFirst()), env: env) {
            var lines: [String] = []
            for try await line in stream {
                let trimmed = line.line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { lines.append(trimmed) }
            }
            harnessBuildOutput = lines.last ?? ""
        } else {
            harnessBuildOutput = ""
        }

        if harnessBuildOutput.isEmpty {
            // Fallback to legacy path construction
            harnessBuildOutput = [
                harnessDir.path + "/.build",
                arch.tripleKey(api: apiLevel, sdkVersion: tc.swiftSDKVersion),
                buildConfig.rawValue,
            ].joined(separator: "/")
        }

        let testHarnessLibSo = "lib\(testHarnessLib).so"
        let harnessLibPath = URL(fileURLWithPath: harnessBuildOutput).appendingPathComponent(testHarnessLibSo, isDirectory: false)
        if !FileManager.default.fileExists(atPath: harnessLibPath.path) {
            throw AndroidError(errorDescription: "Expected test harness library did not exist at: \(harnessLibPath.path)")
        }
        let harnessOutputPath = libDir.appendingPathComponent(testHarnessLibSo, isDirectory: false)
        try FileManager.default.copyItem(at: harnessLibPath, to: harnessOutputPath)

        let testPackagePath = testPackage.replacingOccurrences(of: ".", with: "/")

        // --- Compile Java instrumentation runner ---
        let javaDir = stagingDir.appendingPathComponent("java/\(testPackagePath)", isDirectory: true)
        let classesDir = stagingDir.appendingPathComponent("classes", isDirectory: true)
        let dexDir = stagingDir.appendingPathComponent("dex", isDirectory: true)
        try FileManager.default.createDirectory(at: javaDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: classesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dexDir, withIntermediateDirectories: true)

        try instrumentationJavaSource.write(to: javaDir.appendingPathComponent("\(testClassName).java", isDirectory: false), atomically: true, encoding: .utf8)

        try await runCommand(command: [
            "javac",
            "-source", "8", "-target", "8",
            "-Xlint:-options",
            "-classpath", buildTools.androidJar,
            "-d", classesDir.path,
            javaDir.appendingPathComponent("\(testClassName).java", isDirectory: false).path,
        ], env: env, with: out)

        try await runCommand(command: [
            buildTools.d8,
            "--min-api", "\(apiLevel)",
            "--output", dexDir.path,
            classesDir.appendingPathComponent("\(testPackagePath)/\(testClassName).class", isDirectory: false).path,
        ], env: env, with: out)

        // --- Generate AndroidManifest.xml ---
        let apkPackageName = "\(testPackage).\(packageName.lowercased().replacingOccurrences(of: "-", with: "_"))"
        let manifestXML = generateTestManifest(packageName: apkPackageName, androidAPILevel: apiLevel)
        let manifestFile = stagingDir.appendingPathComponent("AndroidManifest.xml", isDirectory: false)
        try manifestXML.write(to: manifestFile, atomically: true, encoding: .utf8)

        // --- Assemble APK ---
        let unsignedAPK = stagingDir.appendingPathComponent("test.apk", isDirectory: false)

        // Step 1: aapt2 link
        try await runCommand(command: [
            buildTools.aapt2, "link",
            "--manifest", manifestFile.path,
            "-I", buildTools.androidJar,
            "-o", unsignedAPK.path,
        ], env: env, with: out)

        // Step 2: Add native libraries and DEX to the APK
        // Linux/Musl doesn't support the `in workingDirectory` argument, and zip has no flag to set the root folder, so we need to do this shell operation like in:
        // https://github.com/swiftlang/swift-package-manager/blob/e1183984b08c76480406e134a6ec116888cf2e67/Sources/Basics/Archiver/ZipArchiver.swift#L138
        try await run(with: out, "Adding native libraries to APK", ["/bin/sh", "-c", "cd '\(apkContentDir.path)' && zip -r -0 '\(unsignedAPK.path)' lib/"])
        //try await run(with: out, "Adding native libraries to APK", [
        //    "zip", "-r", "-0", unsignedAPK.path, "lib/",
        //], in: apkContentDir)

        try await run(with: out, "Adding classes.dex to APK", [
            "zip", "-j", "-0", unsignedAPK.path, dexDir.appendingPathComponent("classes.dex", isDirectory: false).path,
        ])

        // Step 3: zipalign
        let alignedAPK = unsignedAPK.appendingToLastPathComponent("-aligned")

        try await runCommand(command: [
            buildTools.zipalign, "-f", "-p", "4",
            unsignedAPK.path, alignedAPK.path,
        ], env: env, with: out)

        // Step 4: sign
        let signedAPK = try await signAPK(env, out, buildTools, alignedAPK)

        // --- Install & Execute ---
        let adb = try toolOptions.toolPath(for: "adb")
        let adbEnv = env.filter { $0.key == "ANDROID_SERIAL" }

        // Wait for the device to finish booting before installing — avoids
        // "Can't find service: package" errors on CI where the emulator may
        // still be starting up when we reach this point
        try await waitForDeviceBoot(adb: adb, additionalEnvironment: adbEnv, with: out)

        // Uninstall previous version (permit failure)
        let _ = try? await run(with: out, "Uninstalling previous APK", [adb, "uninstall", apkPackageName], additionalEnvironment: adbEnv, permitFailure: true)

        // Install the APK
        try await run(with: out, "Installing test APK (\(signedAPK.fileSizeString))", [adb, "install", "-t", signedAPK.path], additionalEnvironment: adbEnv)

        // Launch instrumentation and parse structured output
        var testExitCode: Int32 = 1
        var eventLines: [String] = []
        let instrumentLines = try await launchTool("adb", arguments: [
            "shell", "am", "instrument", "-w", "-r",
            "\(apkPackageName)/\(testFullClass)",
        ], env: adbEnv)

        /// https://android.googlesource.com/platform/tools/base/+/master/ddmlib/src/main/java/com/android/ddmlib/testrunner/InstrumentationResultParser.java
        /// E.g.:
        /// ```
        /// INSTRUMENTATION_STATUS_CODE: 1
        /// INSTRUMENTATION_STATUS: class=com.foo.FooTest
        /// INSTRUMENTATION_STATUS: test=testFoo
        /// INSTRUMENTATION_STATUS: numtests=2
        /// INSTRUMENTATION_STATUS: stack=com.foo.FooTest#testFoo:312
        /// INSTRUMENTATION_STATUS_CODE: -2
        ///  ```
        let instrumentationStatusPrefix = "INSTRUMENTATION_STATUS: stream="
        let instrumentationCodePrefix = "INSTRUMENTATION_CODE: "
        let instrumentationResultPrefix = "INSTRUMENTATION_RESULT: "
        var crashMessage: String? = nil
        for try await outputLine in instrumentLines {
            let line = outputLine.line
            //print("RAW OUTPUT: \(line)", to: &TSCBasic.stdoutStream)
            if line.hasPrefix(instrumentationStatusPrefix) {
                let output = String(line.dropFirst(instrumentationStatusPrefix.count))
                if let formatted = formatTestEvent(output, term: outputOptions.term) {
                    print(formatted, to: &TSCBasic.stdoutStream)
                    TSCBasic.stdoutStream.flush()
                }
                eventLines.append(output)
            } else if line.hasPrefix(instrumentationCodePrefix) {
                let code = String(line.dropFirst(instrumentationCodePrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if let c = Int32(code) {
                    testExitCode = (c == -1) ? 0 : c // Android: -1 = Activity.RESULT_OK
                }
            } else if line.hasPrefix(instrumentationResultPrefix) {
                let result = String(line.dropFirst(instrumentationResultPrefix.count))
                if result.contains("shortMsg=Process crashed") || result.contains("shortMsg=process crashed") {
                    crashMessage = result
                }
            } else if line.hasPrefix("INSTRUMENTATION_ABORTED:") || line.contains("Process crashed") {
                crashMessage = crashMessage ?? line
            }
        }

        // Write event stream on host
        if let hostEventPath = eventStreamOutputPath {
            let content = eventLines.joined(separator: "\n") + (eventLines.isEmpty ? "" : "\n")
            try content.write(toFile: hostEventPath, atomically: true, encoding: .utf8)
        }

        // Cleanup
        if cleanup {
            let _ = try? await run(with: out, "Uninstalling test APK", [adb, "uninstall", apkPackageName], additionalEnvironment: adbEnv, permitFailure: true)
        }

        if let crashMessage = crashMessage {
            await out.yield(MessageBlock(status: .fail, "Instrumentation process crashed: \(crashMessage)"))
            throw AndroidError(errorDescription: "Instrumentation process crashed: \(crashMessage)")
        }
        if testExitCode != 0 {
            throw AndroidError(errorDescription: "Test APK exited with code \(testExitCode)")
        }
        #endif
    }

    /// Parses a Swift Testing JSON event record and returns a formatted string for console output,
    /// or `nil` to suppress output for uninteresting events.
    func formatTestEvent(_ json: String, term: Term) -> String? {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["payload"] as? [String: Any],
              let kind = payload["kind"] as? String else {
            return "Warning: could not parse test event: \(json)"
        }

        let messageDicts = payload["messages"] as? [[String: Any]] ?? []
        let messages = messageDicts.compactMap { $0["text"] as? String }
        let symbols = messageDicts.compactMap { $0["symbol"] as? String }

        switch kind {
        case "runStarted":
            return messages.joined(separator: " ")
        case "testStarted":
            let text = messages.first ?? kind
            return "[" + term.cyan("▸") + "] " + text
        case "testEnded":
            let symbol = symbols.first ?? "pass"
            let text = messages.first ?? kind
            if symbol == "pass" || symbol == "passWithKnownIssue" {
                return "[" + term.green("✓") + "] " + text
            } else {
                return "[" + term.red("✗") + "] " + text
            }
        case "testSkipped":
            let text = messages.first ?? kind
            return "[" + term.magenta("-") + "] " + text
        case "issueRecorded":
            var lines: [String] = []
            for (i, msg) in messages.enumerated() {
                let sym = i < symbols.count ? symbols[i] : "default"
                if sym == "fail" {
                    lines.append("[" + term.red("✗") + "] " + term.red(msg))
                } else {
                    lines.append("    " + msg)
                }
            }
            if let issue = payload["issue"] as? [String: Any],
               let loc = issue["sourceLocation"] as? [String: Any],
               let file = (loc["fileID"] as? String) ?? (loc["filePath"] as? String),
               let line = loc["line"] as? Int {
                lines.append("    at \(file):\(line)")
            }
            return lines.joined(separator: "\n")
        case "runEnded":
            let symbol = symbols.first ?? "default"
            let text = messages.first ?? kind
            if symbol == "fail" {
                return "[" + term.red("✗") + "] " + term.red(text)
            } else {
                return "[" + term.green("✓") + "] " + term.green(text)
            }
        default:
            return nil
        }
    }
}


// MARK: - Shared native test-libs staging (Android jniLibs / Darwin Robolectric)

#if canImport(SkipDriveExternal)

/// The platform-varying parts of building + staging the native Swift Testing bundle and its JNI harness.
/// `stageTestLibs` drives the shared pipeline; `androidTestLibsTarget` / `hostTestLibsTarget` supply the
/// Android-vs-Darwin specifics (toolchain build vs host `swift build`, `.so` vs `.dylib`, bundle layout,
/// dependency set, per-ABI vs flat staging, the harness package/source, and any post-staging).
fileprivate struct TestLibsTarget {
    /// The Swift driver used to parse the package and build the harness.
    let swiftCommand: String
    /// The dynamic-library extension for staged artifacts (`so` / `dylib`).
    let dylibExtension: String
    /// Build the test bundle; returns its build-output dir, the environment for the harness build, and
    /// any extra `swift build` arguments for the harness build (e.g. `--swift-sdk` on Android).
    let buildTestBundle: () async throws -> (binDir: URL, harnessEnv: [String: String], harnessExtraArgs: [String])
    /// The loadable Mach-O within the build output (the `.so` itself on Android; the bundle's inner
    /// executable on Darwin).
    let loadableTestBundle: (_ binDir: URL, _ packageName: String) -> URL
    /// The dynamic libraries to stage alongside the test bundle.
    let dependencyLibraries: (_ binDir: URL) throws -> [URL]
    /// The directory to stage the libraries into (per-ABI on Android, flat on Darwin).
    let stagingDirectory: (_ outputDir: String) -> URL
    /// The harness `Package.swift`, and its Swift source given the staged test-lib base name.
    let harnessPackage: String
    let harnessSource: (_ testLibBaseName: String) -> String
    /// Fallback harness build-output dir if `swift build --show-bin-path` yields nothing (Android computes
    /// it from the triple); `nil` to require `--show-bin-path`.
    let harnessBinFallback: (_ harnessDir: URL) -> URL?
    /// Any extra staging once the libraries are in place (Darwin writes `dyld-env.txt`).
    let postStage: (_ libDir: URL) async throws -> Void
}

fileprivate extension AndroidOperationCommand {
    /// The last non-empty stdout line of a tool invocation (used for `--show-bin-path` / `xcode-select`).
    func captureLine(_ tool: String, _ arguments: [String], env: [String: String]) async throws -> String {
        guard let stream = try? await launchTool(tool, arguments: arguments, env: env) else { return "" }
        var lines: [String] = []
        for try await line in stream {
            let trimmed = line.line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        return lines.last ?? ""
    }

    /// Shared pipeline: build the test bundle, stage it + its dependency libraries + the JNI harness into
    /// the target's library directory (jniLibs/`<abi>` or flat), then run any per-target post-staging.
    func stageTestLibs(_ target: TestLibsTarget, outputDir: String, with out: MessageQueue) async throws {
        let buildConfig = toolchainOptions.configuration ?? BuildConfiguration.fromEnvironment() ?? .debug
        let packageDir = toolchainOptions.packagePath ?? "."

        // 1. Build the test bundle (Android toolchain build, or host `swift build`).
        let (binDir, harnessEnv, harnessExtraArgs) = try await target.buildTestBundle()
        let packageName = try await parseSwiftPackage(with: out, at: packageDir, swift: target.swiftCommand).name

        // 2. Locate the loadable test bundle and the directory to stage into.
        let loadable = target.loadableTestBundle(binDir, packageName)
        guard FileManager.default.fileExists(atPath: loadable.path) else {
            throw AndroidError(errorDescription: "Could not find native test bundle at: \(loadable.path)")
        }
        let libDir = target.stagingDirectory(outputDir)
        try? FileManager.default.removeItem(at: libDir)
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)

        // 3. Stage the test bundle (renamed to a loadable lib) + its dependency libraries.
        let testLibName = "lib\(packageName)Test"
        try FileManager.default.copyItem(at: loadable, to: libDir.appendingPathComponent("\(testLibName).\(target.dylibExtension)", isDirectory: false))
        for lib in try target.dependencyLibraries(binDir) {
            let dest = libDir.appendingPathComponent(lib.lastPathComponent, isDirectory: false)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: lib, to: dest)
        }

        // 4. Build the JNI harness that dlopens the test bundle + drives swt, and stage it.
        let stagingDir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: stagingDir) }
        let harnessDir = stagingDir.appendingPathComponent("harness", isDirectory: true)
        let harnessSourceDir = harnessDir.appendingPathComponent("Sources/TestHarness", isDirectory: true)
        try FileManager.default.createDirectory(at: harnessSourceDir, withIntermediateDirectories: true)
        try target.harnessPackage.write(to: harnessDir.appendingPathComponent("Package.swift", isDirectory: false), atomically: true, encoding: .utf8)
        try target.harnessSource(testLibName).write(to: harnessSourceDir.appendingPathComponent("TestRunner.swift", isDirectory: false), atomically: true, encoding: .utf8)

        let harnessPkgArgs = ["--package-path", harnessDir.path, "--configuration", buildConfig.rawValue]
        try await runCommand(command: [target.swiftCommand, "build"] + harnessPkgArgs + harnessExtraArgs, env: harnessEnv, with: out)

        let harnessBinOutput = try await captureLine(target.swiftCommand, ["build", "--show-bin-path"] + harnessPkgArgs + harnessExtraArgs, env: harnessEnv)
        let harnessBinDir: URL
        if !harnessBinOutput.isEmpty {
            harnessBinDir = URL(fileURLWithPath: harnessBinOutput)
        } else if let fallback = target.harnessBinFallback(harnessDir) {
            harnessBinDir = fallback
        } else {
            throw AndroidError(errorDescription: "Could not resolve test harness build output path")
        }
        let harnessLibName = "lib\(testHarnessLib).\(target.dylibExtension)"
        let harnessLib = harnessBinDir.appendingPathComponent(harnessLibName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: harnessLib.path) else {
            throw AndroidError(errorDescription: "Expected test harness library at: \(harnessLib.path)")
        }
        try FileManager.default.copyItem(at: harnessLib, to: libDir.appendingPathComponent(harnessLibName, isDirectory: false))

        // 5. Per-target post-staging (Darwin writes the dynamic-loader env).
        try await target.postStage(libDir)
    }

    /// Android target: builds via the Swift Android SDK toolchain and stages into `<outputDir>/<abi>`
    /// with the Swift-runtime / NDK `.so` dependencies the androidTest APK must carry.
    func androidTestLibsTarget(with out: MessageQueue) async throws -> TestLibsTarget {
        let buildConfig = toolchainOptions.configuration ?? BuildConfiguration.fromEnvironment() ?? .debug
        let packageDir = toolchainOptions.packagePath ?? "."
        let archs = !toolchainOptions.arch.isEmpty ? toolchainOptions.arch : [AndroidArchArgument.current]
        let architectures = archs.flatMap({ $0.architectures(configuration: buildConfig) }).uniqueElements()
        guard let arch = architectures.first else {
            throw AndroidError(errorDescription: "No target architecture specified")
        }
        let apiLevel = toolchainOptions.androidAPILevel
        let tc = try buildToolchainConfiguration(for: arch)
        let swiftCmd = tc.toolchainPath.appendingPathComponent("usr/bin/swift", isDirectory: false).path
        let scratch = toolchainOptions.scratchPath ?? (packageDir + "/.build")
        let buildSystemArgs = args

        return TestLibsTarget(
            swiftCommand: swiftCmd,
            dylibExtension: "so",
            buildTestBundle: {
                let (_, env, binPath) = try await self.runToolchainCommand(tc, executable: nil, testMode: .sharedObject, with: out)
                let binDir: String
                if let binPath = binPath, !binPath.isEmpty {
                    binDir = binPath
                } else {
                    binDir = [scratch, arch.tripleKey(api: apiLevel, sdkVersion: tc.swiftSDKVersion), buildConfig.rawValue].joined(separator: "/")
                }
                var harnessExtra: [String] = []
                if let sdkName = tc.sdkName { harnessExtra += ["--swift-sdk", sdkName] }
                if let bsIndex = buildSystemArgs.firstIndex(of: "--build-system"), bsIndex + 1 < buildSystemArgs.count {
                    harnessExtra += ["--build-system", buildSystemArgs[bsIndex + 1]]
                }
                return (URL(fileURLWithPath: binDir), env, harnessExtra)
            },
            loadableTestBundle: { binDir, packageName in
                binDir.appendingPathComponent("\(packageName)PackageTests.xctest", isDirectory: false)
            },
            dependencyLibraries: { binDir in
                let buildOutputLibraries = try self.files(at: binDir).filter({ $0.lastPathComponent.contains(".so") })
                let sdkLibraries = try self.files(at: tc.libPathDynamic, allowLinks: true)
                    .filter({ $0.lastPathComponent.contains(".so") })
                    .filter({ !builtinLibraries.contains($0.lastPathComponent) })
                let cppShared = try self.files(at: tc.libSysrootArch, allowLinks: true)
                    .filter({ $0.lastPathComponent == "libc++_shared.so" })
                return buildOutputLibraries + sdkLibraries + cppShared
            },
            stagingDirectory: { outputDir in
                URL(fileURLWithPath: outputDir).appendingPathComponent(arch.abi, isDirectory: true)
            },
            harnessPackage: harnessPackageSwift,
            harnessSource: { testLibBaseName in testHarnessSwiftSource(testLibName: "\(testLibBaseName).so") },
            harnessBinFallback: { harnessDir in
                URL(fileURLWithPath: [harnessDir.path + "/.build", arch.tripleKey(api: apiLevel, sdkVersion: tc.swiftSDKVersion), buildConfig.rawValue].joined(separator: "/"))
            },
            postStage: { _ in }
        )
    }

    /// Host target: builds the test bundle + a pure-Swift harness for the host (macOS) and stages them
    /// flat with the Swift-runtime/bridge dylibs and a `dyld-env.txt` for the forked Robolectric JVM.
    func hostTestLibsTarget(with out: MessageQueue) async throws -> TestLibsTarget {
        let buildConfig = toolchainOptions.configuration ?? BuildConfiguration.fromEnvironment() ?? .debug
        let packageDir = toolchainOptions.packagePath ?? "."
        let scratch = toolchainOptions.scratchPath ?? (packageDir + "/.build")
        let dylibSuffix = "dylib" // host build is currently macOS-only

        var buildEnv = ProcessInfo.processInfo.environment
        buildEnv["SKIP_BRIDGE"] = "1"
        let env = buildEnv

        var resolvedSwift = try await captureLine("/usr/bin/xcrun", ["--find", "swift"], env: env)
        if resolvedSwift.isEmpty { resolvedSwift = "swift" }
        let swift = resolvedSwift

        // -DROBOLECTRIC selects the host bridge code paths; -DSKIP_BRIDGE + SKIP_BRIDGE=1 keep bridged
        // library products dynamic so they resolve at load time.
        let testFlags = ["-Xcc", "-fPIC", "-Xswiftc", "-DSKIP_BRIDGE", "-Xswiftc", "-DROBOLECTRIC"]
        let pkgArgs = ["--package-path", packageDir, "--scratch-path", scratch, "-c", buildConfig.rawValue]

        return TestLibsTarget(
            swiftCommand: swift,
            dylibExtension: dylibSuffix,
            buildTestBundle: {
                try await self.runCommand(command: [swift, "build", "--build-tests"] + pkgArgs + testFlags, env: env, with: out)
                let binPath = try await self.captureLine(swift, ["build", "--show-bin-path", "--build-tests"] + pkgArgs + testFlags, env: env)
                guard !binPath.isEmpty else {
                    throw AndroidError(errorDescription: "Could not resolve host test build bin path")
                }
                return (URL(fileURLWithPath: binPath), env, [])
            },
            loadableTestBundle: { binDir, packageName in
                binDir.appendingPathComponent("\(packageName)PackageTests.xctest/Contents/MacOS/\(packageName)PackageTests", isDirectory: false)
            },
            dependencyLibraries: { binDir in
                try self.files(at: binDir).filter({ $0.pathExtension == dylibSuffix })
            },
            stagingDirectory: { outputDir in URL(fileURLWithPath: outputDir) },
            harnessPackage: hostHarnessPackageSwift,
            harnessSource: { testLibBaseName in hostTestHarnessSwiftSource(testLibName: testLibBaseName) },
            harnessBinFallback: { _ in nil },
            postStage: { libDir in
                // Stage the dynamic-loader env so the forked test JVM resolves Testing.framework + the
                // Swift runtime when the harness dlopens the test bundle (linked via @rpath).
                let developerDir = try await self.captureLine("/usr/bin/xcode-select", ["-p"], env: env)
                let platformDev = developerDir + "/Platforms/MacOSX.platform/Developer"
                let dyldEnv = """
                DYLD_FRAMEWORK_PATH=\(platformDev)/Library/Frameworks:\(platformDev)/Library/PrivateFrameworks
                DYLD_LIBRARY_PATH=\(platformDev)/usr/lib:\(libDir.path)
                """
                try dyldEnv.write(to: libDir.appendingPathComponent("dyld-env.txt", isDirectory: false), atomically: true, encoding: .utf8)
            }
        )
    }
}

#endif
