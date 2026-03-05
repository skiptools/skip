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

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Package and run tests as an Android APK"))
    var apk: Bool = false

    @Option(help: ArgumentHelp("Path to write the JSON event stream output", valueName: "path"))
    var eventStreamOutputPath: String? = nil

    /// Any arguments that are not recognized are passed through to the underlying swift build command
    @Argument(parsing: .allUnrecognized, help: ArgumentHelp("Command arguments"))
    var args: [String] = []

    func performCommand(with out: MessageQueue) async throws {
        if apk {
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

        let (_, env) = try await runToolchainCommand(tc, executable: nil, testMode: .sharedObject, with: out)

        let buildOutputFolder = [
            toolchainOptions.scratchPath ?? (packageDir + "/.build"),
            arch.tripleKey(api: apiLevel, sdkVersion: tc.swiftSDKVersion),
            buildConfig.rawValue,
        ].joined(separator: "/")
        let buildOutputFolderURL = URL(fileURLWithPath: buildOutputFolder)

        let packageManifest = try await parseSwiftPackage(with: out, at: packageDir, swift: swiftCmd)
        let packageName = packageManifest.name
        let testLibName = packageName + "PackageTests.xctest"
        let testLibPath = buildOutputFolderURL.appendingPathComponent(testLibName)

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
        try await runCommand(command: harnessCmd, env: env, with: out)

        // Locate the built .so and copy it into the APK lib dir
        let harnessBuildOutput = [
            harnessDir.path + "/.build",
            arch.tripleKey(api: apiLevel, sdkVersion: tc.swiftSDKVersion),
            buildConfig.rawValue,
        ].joined(separator: "/")

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

        // Uninstall previous version (permit failure)
        let _ = try? await run(with: out, "Uninstalling previous APK", [adb, "uninstall", apkPackageName], permitFailure: true)

        // Install the APK
        try await run(with: out, "Installing test APK (\(signedAPK.fileSizeString))", [adb, "install", "-t", signedAPK.path])

        // Launch instrumentation and parse structured output
        var testExitCode: Int32 = 1
        var eventLines: [String] = []
        let instrumentLines = try await launchTool("adb", arguments: [
            "shell", "am", "instrument", "-w", "-r",
            "\(apkPackageName)/\(testFullClass)",
        ])

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
            let _ = try? await run(with: out, "Uninstalling test APK", [adb, "uninstall", apkPackageName], permitFailure: true)
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

private let testHarnessLib = "test_harness"
private let testPackage = "org.swift.test"
private let testClassName = "SwiftTestRunner"
private let testFullClass = "\(testPackage).\(testClassName)"

/// Package.swift for the generated Swift test harness package.
/// Defines a dynamic library target that produces `libtest_harness.so`
private let harnessPackageSwift: String = """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "test-harness",
    products: [
        .library(name: "\(testHarnessLib)", type: .dynamic, targets: ["TestHarness"])
    ],
    targets: [
        .target(
            name: "TestHarness",
            linkerSettings: [
                .linkedLibrary("log"),
                .linkedLibrary("dl"),
            ]
        ),
    ]
)
"""

/// Java source for the Android Instrumentation test runner.
/// Loads `libtest_harness.so`, calls `runTests()` via JNI, and uses
/// `sendStatus()`/`finish()` for structured output back to the host.
private let instrumentationJavaSource: String = """
package \(testPackage);

import android.app.Instrumentation;
import android.os.Bundle;

public class \(testClassName) extends Instrumentation {
    static {
        android.util.Log.i("SwiftTest", "loading harness");
        System.loadLibrary("\(testHarnessLib)");
        android.util.Log.i("SwiftTest", "loaded harness");
    }
    private native int runTests();

    @Override
    public void onCreate(Bundle arguments) {
        android.util.Log.i("SwiftTest", "onCreate");
        super.onCreate(arguments);
        // This triggers onStart() in a separate thread
        start();
        android.util.Log.i("SwiftTest", "onCreate: started");
    }

    @Override
    public void onStart() {
        super.onStart();
        Bundle result = new Bundle();
        try {
            android.util.Log.i("SwiftTest", "onStart");
            super.onStart();
            android.util.Log.i("SwiftTest", "runTests");
            int exitCode = runTests();
            android.util.Log.i("SwiftTest", "runTests done");
            result.putString("status", exitCode == 0 ? "passed" : "failed");
            finish(exitCode == 0 ? -1 : exitCode, result);
        } catch (Throwable t) {
            android.util.Log.e("SwiftTest", "Test error", t);
            finish(1, result);
        }
    }

    public void reportTestOutput(String line) {
        Bundle b = new Bundle();
        b.putString("stream", line + "\\n");
        sendStatus(0, b);
    }
}
"""

/// Swift source for the test harness. Implements JNI_OnLoad and the native `runTests` method.
/// Loads the test library via dlopen, invokes the Swift Testing entry point, and reports
/// test output back through JNI to the Java Instrumentation runner.
private func testHarnessSwiftSource(testLibName: String) -> String {
    return """
import Android
import Dispatch

// MARK: - JNI type aliases

typealias JNIEnvironment = UnsafeMutablePointer<JNIEnv?>

// MARK: - Global state

nonisolated(unsafe) var g_jvm: UnsafeMutablePointer<JavaVM?>? = nil

private func androidLog(_ priority: android_LogPriority, _ tag: String, _ message: String) {
    __android_log_write(Int32(priority.rawValue), tag, message)
}

// MARK: - JNI_OnLoad

@_cdecl("JNI_OnLoad")
func JNI_OnLoad(_ vm: UnsafeMutablePointer<JavaVM?>?, _ reserved: UnsafeMutableRawPointer?) -> jint {
    g_jvm = vm
    androidLog(ANDROID_LOG_INFO, "SwiftTest", "JNI_OnLoad")
    return jint(JNI_VERSION_1_6)
}

// MARK: - Entry point type (ST-0002 JSON ABI)

typealias EntryPoint = @convention(thin) @Sendable (
    _ configurationJSON: UnsafeRawBufferPointer?,
    _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
) async throws -> Bool

// MARK: - JNI native method

@_cdecl("Java_\(testFullClass.replacingOccurrences(of: ".", with: "_"))_runTests")
func runTests(_ env: JNIEnvironment, _ thisObj: jobject) -> jint {
    let jni: JNINativeInterface = env.pointee!.pointee

    // Keep a global ref to the Instrumentation object for use from other threads
    guard let globalThis: jobject = jni.NewGlobalRef(env, thisObj) else {
        androidLog(ANDROID_LOG_ERROR, "SwiftTest", "Failed to create global ref")
        return 1
    }
    defer { jni.DeleteGlobalRef(env, globalThis) }

    // Load test library
    androidLog(ANDROID_LOG_INFO, "SwiftTest", "Loading test library: \(testLibName)")
    guard let handle = dlopen("\(testLibName)", RTLD_NOW) else {
        let err = dlerror().flatMap({ String(cString: $0) }) ?? ""
        androidLog(ANDROID_LOG_ERROR, "SwiftTest", "dlopen failed: \\(err)")
        return 1
    }

    // Look up swt_abiv0_getEntryPoint
    guard let sym = dlsym(handle, "swt_abiv0_getEntryPoint") else {
        androidLog(ANDROID_LOG_ERROR, "SwiftTest", "swt_abiv0_getEntryPoint not found")
        return 1
    }
    typealias GetEntryPointFn = @convention(c) () -> UnsafeRawPointer?
    let getEntryPoint = unsafeBitCast(sym, to: GetEntryPointFn.self)

    guard let rawEntryPoint = getEntryPoint() else {
        androidLog(ANDROID_LOG_ERROR, "SwiftTest", "swt_abiv0_getEntryPoint returned NULL")
        return 1
    }
    let entryPoint = unsafeBitCast(rawEntryPoint, to: EntryPoint.self)

    androidLog(ANDROID_LOG_INFO, "SwiftTest", "Running Swift Testing...")

    // wrap the jobject in a Sendable so it can be passed into the Task
    struct SendableJobject: @unchecked Sendable {
        let value: jobject
    }

    let gThis = SendableJobject(value: globalThis)
    // Record handler: report each JSON record back through JNI
    let recordHandler: @Sendable (UnsafeRawBufferPointer) -> Void = { recordJSON in
        guard let base = recordJSON.baseAddress, recordJSON.count > 0 else { return }
        let json = String(
            decoding: UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: recordJSON.count),
            as: UTF8.self
        )
        reportToJava(globalRef: gThis.value, line: json)
    }

    // Bridge sync → async via DispatchSemaphore
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var testSuccess = false
    Task {
        defer { semaphore.signal() }
        do {
            testSuccess = try await entryPoint(nil, recordHandler)
        } catch {
            androidLog(ANDROID_LOG_ERROR, "SwiftTest", "Entry point threw error: \\(error)")
        }
    }
    semaphore.wait()

    let exitCode: Int32 = testSuccess ? 0 : 1
    return jint(exitCode)
}

// MARK: - JNI callback to Java

/// Calls `\(testClassName).reportTestOutput(String)` via JNI.
/// Handles thread attachment for cooperative pool threads.
private func reportToJava(globalRef: jobject, line: String) {
    androidLog(ANDROID_LOG_INFO, "SwiftTest", "Test line: \\(line)")

    guard let jvm = g_jvm else { return }
    let jii: JNIInvokeInterface = jvm.pointee!.pointee

    var envPtr: UnsafeMutableRawPointer? = nil
    let getResult = jii.GetEnv(jvm, &envPtr, jint(JNI_VERSION_1_6))

    var needsDetach = false
    if getResult == JNI_EDETACHED {
        var attachedPtr: UnsafeMutablePointer<JNIEnv?>? = nil
        guard jii.AttachCurrentThread(jvm, &attachedPtr, nil) == JNI_OK else {
            return
        }
        if let attachedPtr {
            envPtr = UnsafeMutableRawPointer(attachedPtr)
        }
        needsDetach = true
    } else if getResult != JNI_OK {
        return
    }
    defer { if needsDetach { _ = jii.DetachCurrentThread(jvm) } }

    guard let rawEnv = envPtr else { return }
    let env = rawEnv.assumingMemoryBound(to: JNIEnv?.self)
    let jni: JNINativeInterface = env.pointee!.pointee

    guard let cls: jclass = jni.GetObjectClass(env, globalRef) else { return }

    let methodName = "reportTestOutput"
    let methodSig = "(Ljava/lang/String;)V"
    guard let mid: jmethodID = methodName.withCString({ name in
        methodSig.withCString({ sig in
            jni.GetMethodID(env, cls, name, sig)
        })
    }) else { return }

    guard let jstr = line.withCString({ cstr in
        jni.NewStringUTF(env, cstr)
    }) else { return }

    let args = [jvalue(l: jstr)]
    args.withUnsafeBufferPointer { buf in
        jni.CallVoidMethodA(env, globalRef, mid, buf.baseAddress)
    }
}
"""
}
