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
        let zipalign = latestVersion.appendingPathComponent("zipalign", isDirectory: false).path
        let apksigner = latestVersion.appendingPathComponent("apksigner", isDirectory: false).path

        for (name, path) in [("aapt2", aapt2), ("zipalign", zipalign), ("apksigner", apksigner)] {
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

        return AndroidBuildTools(aapt2: aapt2, zipalign: zipalign, apksigner: apksigner, androidJar: androidJar)
    }

    /// Generate an AndroidManifest.xml for the test APK
    func generateTestManifest(packageName: String, libName: String, androidAPILevel: Int) -> String {
        return """
            <?xml version="1.0" encoding="utf-8"?>
            <manifest xmlns:android="http://schemas.android.com/apk/res/android"
                package="\(packageName)">
                <application android:hasCode="false" android:label="SwiftTest">
                    <activity android:name="android.app.NativeActivity"
                        android:exported="true">
                        <meta-data android:name="android.app.lib_name" android:value="\(libName)" />
                        <intent-filter>
                            <action android:name="android.intent.action.MAIN" />
                            <category android:name="android.intent.category.LAUNCHER" />
                        </intent-filter>
                    </activity>
                </application>
                <uses-sdk android:minSdkVersion="\(androidAPILevel)" android:targetSdkVersion="\(androidAPILevel)" />
            </manifest>
            """
    }

    /// Build Swift tests as a shared library, package into an APK, install, launch, and stream test output via logcat.
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
        defer { try? FileManager.default.removeItem(at: stagingDir) }

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

        let deviceEventPath = "/data/local/tmp/swift-test-events.jsonl"
        let harnessCSource = testHarnessCSource(
            testLibName: "lib\(packageName)Test.so",
            eventStreamDevicePath: eventStreamOutputPath != nil ? deviceEventPath : nil
        )

        // Create package directory structure:
        //   harness/Package.swift
        //   harness/Sources/CAndroid/include/CAndroid.h
        //   harness/Sources/CAndroid/test_harness.c
        //   harness/Sources/TestHarness/TestRunner.swift
        let cAndroidIncludeDir = harnessDir.appendingPathComponent("Sources/CAndroid/include", isDirectory: true)
        let cAndroidSourceDir = harnessDir.appendingPathComponent("Sources/CAndroid", isDirectory: true)
        let testHarnessSourceDir = harnessDir.appendingPathComponent("Sources/TestHarness", isDirectory: true)
        try FileManager.default.createDirectory(at: cAndroidIncludeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testHarnessSourceDir, withIntermediateDirectories: true)

        try testHarnessPackageSwift.write(to: harnessDir.appendingPathComponent("Package.swift", isDirectory: false), atomically: true, encoding: .utf8)
        try testHarnessCHeader.write(to: cAndroidIncludeDir.appendingPathComponent("CAndroid.h", isDirectory: false), atomically: true, encoding: .utf8)
        try harnessCSource.write(to: cAndroidSourceDir.appendingPathComponent("\(test_harness).c", isDirectory: false), atomically: true, encoding: .utf8)
        try testHarnessSwiftSource.write(to: testHarnessSourceDir.appendingPathComponent("TestRunner.swift", isDirectory: false), atomically: true, encoding: .utf8)

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
        let harnessLibPath = URL(fileURLWithPath: harnessBuildOutput).appendingPathComponent("lib\(test_harness).so", isDirectory: false)
        if !FileManager.default.fileExists(atPath: harnessLibPath.path) {
            throw AndroidError(errorDescription: "Expected test harness library did not exist at: \(harnessLibPath.path)")
        }
        let harnessOutputPath = libDir.appendingPathComponent("lib\(test_harness).so", isDirectory: false)
        try FileManager.default.copyItem(at: harnessLibPath, to: harnessOutputPath)

        // --- Generate AndroidManifest.xml ---
        let apkPackageName = "com.swift.test.\(packageName.lowercased().replacingOccurrences(of: "-", with: "_"))"
        let manifestXML = generateTestManifest(packageName: apkPackageName, libName: test_harness, androidAPILevel: apiLevel)
        let manifestFile = stagingDir.appendingPathComponent("AndroidManifest.xml", isDirectory: false)
        try manifestXML.write(to: manifestFile, atomically: true, encoding: .utf8)

        // --- Assemble APK ---
        let unsignedAPK = stagingDir.appendingPathComponent("test-unsigned.apk", isDirectory: false)
        let alignedAPK = stagingDir.appendingPathComponent("test-aligned.apk", isDirectory: false)
        let finalAPK = stagingDir.appendingPathComponent("test.apk", isDirectory: false)

        // Step 1: aapt2 link
        try await runCommand(command: [
            buildTools.aapt2, "link",
            "--manifest", manifestFile.path,
            "-I", buildTools.androidJar,
            "-o", unsignedAPK.path,
        ], env: env, with: out)

        // Step 2: Add native libraries to the APK (zip -r -0 from apk-content dir)
        try await run(with: out, "Adding native libraries to APK", [
            "zip", "-r", "-0", unsignedAPK.path, "lib/",
        ], in: apkContentDir)

        // Step 3: zipalign
        try await runCommand(command: [
            buildTools.zipalign, "-f", "-p", "4",
            unsignedAPK.path, alignedAPK.path,
        ], env: env, with: out)

        // Step 4: Sign with debug keystore
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

        // Step 5: apksigner sign
        try await runCommand(command: [
            buildTools.apksigner, "sign",
            "--ks", debugKeystorePath,
            "--ks-pass", "pass:android",
            "--ks-key-alias", "androiddebugkey",
            "--key-pass", "pass:android",
            "--out", finalAPK.path,
            alignedAPK.path,
        ], env: env, with: out)

        // --- Install & Execute ---
        let adb = try toolOptions.toolPath(for: "adb")
        let activityComponent = "\(apkPackageName)/android.app.NativeActivity"

        // Uninstall previous version (permit failure)
        let _ = try? await run(with: out, "Uninstalling previous APK", [adb, "uninstall", apkPackageName], permitFailure: true)

        // Install the APK
        try await run(with: out, "Installing test APK", [adb, "install", "-t", finalAPK.path])

        // Clear logcat
        try await run(with: out, "Clearing logcat", [adb, "logcat", "-c"])

        // Launch the activity
        try await run(with: out, "Launching test activity", [adb, "shell", "am", "start", "-n", activityComponent])

        // Monitor logcat for test output
        var testExitCode: Int32 = -1
        let sentinel = "\(SWIFT_TEST_EXIT_CODE)="
        let logcatLines = try await launchTool("adb", arguments: ["logcat", "-s", "SwiftTest:I", "-v", "raw"])
        for try await outputLine in logcatLines {
            let line = outputLine.line
            print(line, to: &TSCBasic.stdoutStream)
            TSCBasic.stdoutStream.flush()

            if let range = line.range(of: sentinel) {
                let codeStr = line[range.upperBound...]
                if let code = Int32(codeStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    testExitCode = code
                    break
                }
            }
        }

        // Pull event stream file from device if --event-stream-output-path was specified
        if let hostEventPath = eventStreamOutputPath {
            let _ = try? await run(with: out, "Pulling event stream", [adb, "pull", deviceEventPath, hostEventPath], permitFailure: true)
            let _ = try? await run(with: out, "Cleaning up device event file", [adb, "shell", "rm", "-f", deviceEventPath], permitFailure: true)
        }

        // Cleanup
        if cleanup {
            let _ = try? await run(with: out, "Uninstalling test APK", [adb, "uninstall", apkPackageName], permitFailure: true)
        }

        if testExitCode != 0 {
            throw AndroidError(errorDescription: "Test APK exited with code \(testExitCode)")
        }
        #endif
    }

}

private let test_harness = "test_harness"
let SWIFT_TEST_EXIT_CODE = "SWIFT_TEST_EXIT_CODE"

/// Package.swift for the generated Swift test harness package.
/// Defines a dynamic library target that produces `libtest_harness.so`,
/// with a CAndroid helper target for Android NDK C headers.
private let testHarnessPackageSwift: String = """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "test-harness",
    products: [
        .library(name: "\(test_harness)", type: .dynamic, targets: ["CAndroid", "TestHarness"])
    ],
    targets: [
        .target(
            name: "CAndroid",
            linkerSettings: [
                .linkedLibrary("android"),
                .linkedLibrary("log"),
                .linkedLibrary("dl"),
            ]
        ),
        .target(
            name: "TestHarness",
            dependencies: ["CAndroid"],
            linkerSettings: [
                .linkedLibrary("android"),
                .linkedLibrary("log"),
                .linkedLibrary("dl"),
            ]
        ),
    ]
)
"""

/// C umbrella header for the CAndroid module, providing Android NDK and POSIX headers.
/// Includes convenience wrappers around `__android_log_print` for Swift interop
/// (Swift cannot call variadic C functions directly).
private let testHarnessCHeader: String = """
#pragma once

#include <android/native_activity.h>
#include <android/log.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>

// Convenience wrappers for __android_log_print (Swift cannot call variadic C functions directly)
static inline void android_log_print_info(const char *tag, const char *msg) {
    __android_log_print(ANDROID_LOG_INFO, tag, "%s", msg);
}
static inline void android_log_print_error(const char *tag, const char *msg) {
    __android_log_print(ANDROID_LOG_ERROR, tag, "%s", msg);
}

// Called from the Swift record handler to write JSON test records to stdout (-> logcat) and the event stream file
void handle_test_record(const char *json, size_t len);
"""

/// C source for the APK test harness that handles NativeActivity lifecycle, stdio→logcat
/// redirection, library loading, dlsym, thread management, and exit code sentinel.
/// Calls `run_swift_tests()` (defined in Swift) for the async entry point invocation.
private func testHarnessCSource(testLibName: String, eventStreamDevicePath: String?) -> String {
    let eventStreamLiteral: String
    if let path = eventStreamDevicePath {
        eventStreamLiteral = "\"\(path)\""
    } else {
        eventStreamLiteral = "NULL"
    }

    return """
#include "include/CAndroid.h"

// Declaration of the Swift function that bridges to async and invokes the entry point
extern int32_t run_swift_tests(const void *entry_point);

#define TAG "SwiftTest"
#define TEST_LIB_NAME "\(testLibName)"

static ANativeActivity *g_activity = NULL;
static int g_event_fd = -1;

// --- Record handling ---

void handle_test_record(const char *json, size_t len) {
    // Write to stdout (redirected to logcat via log_reader threads)
    fwrite(json, 1, len, stdout);
    if (len == 0 || json[len - 1] != '\\n') {
        fputc('\\n', stdout);
    }
    fflush(stdout);
    // Write to event stream file
    if (g_event_fd >= 0) {
        write(g_event_fd, json, len);
        if (len == 0 || json[len - 1] != '\\n') {
            write(g_event_fd, "\\n", 1);
        }
    }
}

// --- Logcat redirection ---

static void *log_reader(void *arg) {
    int fd = (int)(intptr_t)arg;
    char buf[4096];
    while (1) {
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        if (n <= 0) break;
        buf[n] = '\\0';
        // Split on newlines and log each line
        char *start = buf;
        for (ssize_t i = 0; i < n; i++) {
            if (buf[i] == '\\n') {
                buf[i] = '\\0';
                __android_log_print(ANDROID_LOG_INFO, TAG, "%s", start);
                start = &buf[i + 1];
            }
        }
        if (*start != '\\0') {
            __android_log_print(ANDROID_LOG_INFO, TAG, "%s", start);
        }
    }
    return NULL;
}

static void redirect_stdio(void) {
    int stdout_pipe[2], stderr_pipe[2];
    pipe(stdout_pipe);
    pipe(stderr_pipe);
    dup2(stdout_pipe[1], STDOUT_FILENO);
    dup2(stderr_pipe[1], STDERR_FILENO);
    close(stdout_pipe[1]);
    close(stderr_pipe[1]);

    pthread_t t1, t2;
    pthread_create(&t1, NULL, log_reader, (void *)(intptr_t)stdout_pipe[0]);
    pthread_create(&t2, NULL, log_reader, (void *)(intptr_t)stderr_pipe[0]);
    pthread_detach(t1);
    pthread_detach(t2);
}

// --- Test runner ---

static void *test_runner(void *arg) {
    redirect_stdio();

    __android_log_print(ANDROID_LOG_INFO, TAG, "Loading test library: %s", TEST_LIB_NAME);

    void *handle = dlopen(TEST_LIB_NAME, RTLD_NOW);
    if (!handle) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "dlopen failed: %s", dlerror());
        __android_log_print(ANDROID_LOG_INFO, TAG, "\(SWIFT_TEST_EXIT_CODE)=1");
        if (g_activity) ANativeActivity_finish(g_activity);
        return NULL;
    }

    // Look up swt_abiv0_getEntryPoint per ST-0002 JSON ABI
    typedef const void *(*GetEntryPointFn)(void);
    GetEntryPointFn getEntryPoint = (GetEntryPointFn)dlsym(handle, "swt_abiv0_getEntryPoint");
    if (!getEntryPoint) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "swt_abiv0_getEntryPoint not found");
        __android_log_print(ANDROID_LOG_INFO, TAG, "\(SWIFT_TEST_EXIT_CODE)=1");
        if (g_activity) ANativeActivity_finish(g_activity);
        return NULL;
    }

    const void *entryPoint = getEntryPoint();
    if (!entryPoint) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "swt_abiv0_getEntryPoint returned NULL");
        __android_log_print(ANDROID_LOG_INFO, TAG, "\(SWIFT_TEST_EXIT_CODE)=1");
        if (g_activity) ANativeActivity_finish(g_activity);
        return NULL;
    }

    __android_log_print(ANDROID_LOG_INFO, TAG, "Swift Testing entry point obtained");
    __android_log_print(ANDROID_LOG_INFO, TAG, "Running Swift Testing...");

    // Open event stream file if configured
    const char *event_stream_path = \(eventStreamLiteral);
    if (event_stream_path) {
        g_event_fd = open(event_stream_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }

    // Delegate async invocation to Swift
    int32_t exitCode = run_swift_tests(entryPoint);

    // Close event stream file
    if (g_event_fd >= 0) { close(g_event_fd); g_event_fd = -1; }

    // exit code 69 (EX_UNAVAILABLE) means no tests found — not a failure
    if (exitCode == 69) exitCode = 0;

    fflush(stdout);
    fflush(stderr);
    // give log_reader threads time to drain pipes
    usleep(500000);

    __android_log_print(ANDROID_LOG_INFO, TAG, "\(SWIFT_TEST_EXIT_CODE)=%d", exitCode);
    if (g_activity) ANativeActivity_finish(g_activity);
    return NULL;
}

// --- NativeActivity entry point ---

void ANativeActivity_onCreate(ANativeActivity *activity, void *savedState, size_t savedStateSize) {
    g_activity = activity;
    pthread_t tid;
    pthread_create(&tid, NULL, test_runner, NULL);
    pthread_detach(tid);
}
"""
}

/// Minimal Swift source for the APK test harness.
/// Only bridges sync C → async Swift to invoke the testing entry point.
/// All I/O (logcat, event stream, record writing) is handled in C.
private let testHarnessSwiftSource: String = """
import CAndroid
import Dispatch

/// Entry point type per ST-0002 JSON ABI.
typealias EntryPoint = @convention(thin) @Sendable (
    _ configurationJSON: UnsafeRawBufferPointer?,
    _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
) async throws -> Bool

/// Called from C with the raw entry point pointer.
/// Bridges to async, invokes the entry point, and returns the exit code.
@_cdecl("run_swift_tests")
public func runSwiftTests(_ entryPointRaw: UnsafeRawPointer) -> Int32 {
    let entryPoint = unsafeBitCast(entryPointRaw, to: EntryPoint.self)

    // Record handler: delegate to C for stdout/logcat and event stream writing
    let recordHandler: @Sendable (UnsafeRawBufferPointer) -> Void = { recordJSON in
        if let base = recordJSON.baseAddress, recordJSON.count > 0 {
            handle_test_record(base.assumingMemoryBound(to: CChar.self), recordJSON.count)
        }
    }

    // Bridge sync context to async Swift via DispatchSemaphore
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var testSuccess = false
    Task {
        defer { semaphore.signal() }
        do {
            testSuccess = try await entryPoint(nil, recordHandler)
        } catch {
            android_log_print_error("SwiftTest", "Entry point threw error: \\(error)")
        }
    }
    semaphore.wait()

    return testSuccess ? 0 : 1
}
"""

