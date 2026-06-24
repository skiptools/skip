// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

// MARK: - Shared native Swift Testing harness sources
//
// These define the JNI bridge that loads a native Swift Testing test library (`*.xctest`/`*.so`,
// which exports `swt_abiv0_getEntryPoint`) and drives the Swift Testing ABI-v0 entry point, reporting
// each JSON event record back to a Java/Kotlin `Instrumentation` via `reportTestOutput(String)`.
//
// Two consumers share these sources:
//   - `skip android test --apk` (AndroidTestCommand.runSwiftPMAsAPK): hand-assembles a bare APK.
//   - the `skip test` native-harness path (NativeTestRun): packages the same runner via a generated
//     Gradle test-harness module so the Skip Kotlin bridge libraries + merged assets are present
//     (which the bare `--apk` APK lacks — that is why localization crashes there with `JNI.jni was unset`).
//
// The Gradle path needs the runner to additionally initialise the Skip bridge (load the bridge native
// libraries → `JNI_OnLoad` sets `JNI.jni`; establish the Android `Context`; run `initAndroidBridge`)
// before invoking the entry point — see `swiftTestRunnerJavaSource(initBridge:)`.

/// The library name produced by the Swift test harness package (`libtest_harness.so`).
let testHarnessLib = "test_harness"
/// The Java package + class of the instrumentation runner. Its name fixes the JNI symbol the harness
/// exports (`Java_<package>_<class>_runTests`), so the harness Swift source is generated from it.
let testPackage = "org.swift.test"
let testClassName = "SwiftTestRunner"
let testFullClass = "\(testPackage).\(testClassName)"

/// Package.swift for the generated Swift test harness package.
/// Defines a dynamic library target that produces `libtest_harness.so`.
let harnessPackageSwift: String = """
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
                .linkedLibrary("android"), // for the NDK ALooper_* functions used by setupMainLooper
            ]
        ),
    ]
)
"""

/// Java source for the Android Instrumentation test runner.
/// Loads `libtest_harness.so`, calls `runTests()` via JNI, and uses
/// `sendStatus()`/`finish()` for structured output back to the host.
///
/// - Parameter initBridge: when true, initialise the Skip Android bridge (so `JNI.jni`, the Android
///   `Context`, and Foundation bootstrap are established before the native test runs — required for
///   tests that touch the Kotlin bridge, e.g. `String(localized:bundle:.module)`). The `--apk` path
///   passes `false` (bare APK with no bridge); the Gradle-harness path passes `true`.
func swiftTestRunnerJavaSource(initBridge: Bool) -> String {
    let bridgeInit = initBridge ? """
                // Initialise the Skip bridge so the native test can call into the Kotlin-side Skip
                // libraries (JNI, Android Context, localized Bundle assets). This loads the bridge
                // native libraries listed in the merged manifest's SKIP_BRIDGE_MODULES meta-data.
                try {
                    android.util.Log.i("SwiftTest", "launching Skip bridge");
                    skip.foundation.ProcessInfo.Companion.launch(getContext());
                } catch (Throwable t) {
                    android.util.Log.e("SwiftTest", "Skip bridge launch failed", t);
                }

    """ : ""

    return """
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
            private native boolean setupMainLooper();

            @Override
            public void onCreate(Bundle arguments) {
                android.util.Log.i("SwiftTest", "onCreate");
                // Wire the Swift main DispatchQueue into THIS (main) thread's Android Looper before any
                // test job is created, so MainActor/main-queue work scheduled by the run can drain.
                boolean looper = setupMainLooper();
                android.util.Log.i("SwiftTest", "setupMainLooper=" + looper);
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
        \(bridgeInit)            android.util.Log.i("SwiftTest", "runTests");
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
}

/// The bare-APK instrumentation runner (no bridge init), used by `skip android test --apk`.
let instrumentationJavaSource: String = swiftTestRunnerJavaSource(initBridge: false)

// MARK: - Conventional `mode: native` test module (Gradle connectedAndroidTest) generation

/// Kotlin source for the on-device `AndroidJUnit4` test generated into a `mode: native` test module's
/// `src/androidTest/kotlin/org/swift/test/SwiftTestRunner.kt`. Loads `libtest_harness.so`, drains the
/// Swift main queue on the main thread, runs the Swift Testing suite (which `dlopen`s the test bundle),
/// and asserts success — so AGP's `connectedDebugAndroidTest` produces a JUnit result for `skip test`.
let nativeTestRunnerKotlinSource: String = """
// Auto-generated by Skip — do not edit
package \(testPackage)

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class \(testClassName) {
    private external fun setupMainLooper(): Boolean
    private external fun runTests(): Int

    // The native harness reports each Swift Testing JSON event record here (via reportToJava). Logging it
    // under the "SwiftTest" tag lets the Gradle block recover the per-test event stream from logcat after
    // the connected run (which survives AGP uninstalling the test APK), so `skip test` can report per-test
    // results instead of the single aggregate case.
    fun reportTestOutput(line: String) { android.util.Log.i("SwiftTest", line) }

    @Test fun nativeSwiftTests() {
        System.loadLibrary("\(testHarnessLib)")
        // Wire the Swift main DispatchQueue into the device main Looper before running the suite.
        InstrumentationRegistry.getInstrumentation().runOnMainSync { setupMainLooper() }
        assertEquals("native Swift Testing cases should all pass", 0, runTests())
    }
}
"""

/// Gradle DSL appended to a `mode: native` test module's under-test `build.gradle.kts`. Registers a
/// `buildAndroidSwiftTestLibs` task that runs `skip android test --build-test-libs` (building the test
/// bundle + `libtest_harness.so` + Swift-runtime/bridge `.so` deps into `<build>/test-jni-libs/<abi>`),
/// adds that folder to the androidTest jniLibs, and hooks it before the androidTest native-lib merge.
/// Relies on `swiftBuildFolder()` / `swiftSourceFolder()` / `skipcmd` / `skipCommand` / `SkipBridgeExecOps`
/// defined by the native build block (skip-bridge's skip.yml) that the under-test module already carries.
let nativeTestGradleBlock: String = """
// Native Swift Testing (`mode: native` test module) support generated by Skip
android {
    sourceSets {
        getByName("androidTest") {
            jniLibs.srcDir("${swiftBuildFolder()}/test-jni-libs")
        }
    }
    defaultConfig {
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
}

tasks.configureEach {
    if ((name == "mergeDebugAndroidTestJniLibFolders" || name == "mergeReleaseAndroidTestJniLibFolders") && (System.getenv("SKIP_BRIDGE_ANDROID_BUILD_DISABLED") != "1")) {
        dependsOn("buildAndroidSwiftTestLibs")
    }
}

tasks.register("buildAndroidSwiftTestLibs") {
    doLast {
        project.objects.newInstance<SkipBridgeExecOps>().execOps.exec {
            workingDir(layout.projectDirectory)
            commandLine("sh", "-cx", "\\"${skipcmd}\\" android test --build-test-libs \\"${swiftBuildFolder()}/test-jni-libs\\" --package-path \\"${swiftSourceFolder()}\\" --configuration debug --scratch-path \\"${swiftBuildFolder()}/swift-test\\" --arch automatic --build-system native")
            environment("SKIP_BRIDGE", "1")
            environment("TARGET_OS_ANDROID", "1")
            environment("DEVELOPER_DIR", "")
            if (file(skipCommand).exists()) { environment("SKIP_COMMAND_OVERRIDE", skipCommand) }
        }
    }
}

// Recover per-test results for a connected (device/emulator) androidTest run from logcat: the runner logs
// each swt event record under the "SwiftTest" tag, so we clear logcat before the run and dump it (raw,
// tag-filtered) afterward into the host connected-results dir, where `skip test` looks for the event
// stream. Using logcat (rather than a pulled on-device file) survives AGP uninstalling the test APK after
// the run, and needs no package name. Best-effort: on failure the parser finds no events and the aggregate
// row is used. `swtAdbArgs` prefixes `adb` (+ `-s <serial>` when ANDROID_SERIAL is set) to the given args.
val swtAdb = (System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT"))?.let { "${it}/platform-tools/adb" } ?: "adb"
fun swtAdbArgs(vararg extra: String): List<String> {
    val args = mutableListOf(swtAdb)
    val serial = System.getenv("ANDROID_SERIAL")
    if (serial != null && serial.isNotEmpty()) { args.add("-s"); args.add(serial) }
    args.addAll(extra)
    return args
}
tasks.configureEach {
    if (name == "connectedDebugAndroidTest" || name == "connectedReleaseAndroidTest") {
        val swtConfig = if (name.contains("Release")) "release" else "debug"
        doFirst {
            try {
                project.objects.newInstance<SkipBridgeExecOps>().execOps.exec {
                    commandLine(swtAdbArgs("logcat", "-c"))
                    isIgnoreExitValue = true
                }
            } catch (e: Throwable) { }
        }
        doLast {
            try {
                val swtHostDir = layout.buildDirectory.dir("outputs/androidTest-results/connected/" + swtConfig).get().asFile
                swtHostDir.mkdirs()
                swtHostDir.resolve("swt-events.jsonl").outputStream().use { os ->
                    project.objects.newInstance<SkipBridgeExecOps>().execOps.exec {
                        commandLine(swtAdbArgs("logcat", "-d", "-v", "raw", "-s", "SwiftTest:I"))
                        standardOutput = os
                        isIgnoreExitValue = true
                    }
                }
            } catch (e: Throwable) { }
        }
    }
}
"""

/// Swift source for the test harness. Implements JNI_OnLoad and the native `runTests` method.
/// Loads the test library via dlopen, invokes the Swift Testing entry point, and reports
/// test output back through JNI to the Java Instrumentation runner.
func testHarnessSwiftSource(testLibName: String) -> String {
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

// MARK: - Main looper setup (must run ON THE MAIN THREAD, before the test runs)

// libdispatch internals (no CoreFoundation): the port of the Swift main DispatchQueue, and the
// callback that drains its pending work. These are what CFRunLoop's main-queue integration uses.
@_silgen_name("_dispatch_main_queue_callback_4CF")
func _dispatch_main_queue_callback_4CF()
@_silgen_name("_dispatch_get_main_queue_port_4CF")
func _dispatch_get_main_queue_port_4CF() -> Int32

// NDK android/looper.h functions (from libandroid.so), declared directly to avoid importing
// AndroidLooper (which pulls in CoreFoundation). ALOOPER_EVENT_INPUT == (1 << 0).
private let ALOOPER_EVENT_INPUT: CInt = 1
@_silgen_name("ALooper_forThread")
func ALooper_forThread() -> OpaquePointer?
@_silgen_name("ALooper_acquire")
func ALooper_acquire(_ looper: OpaquePointer?)
@_silgen_name("ALooper_addFd")
func ALooper_addFd(_ looper: OpaquePointer?, _ fd: CInt, _ ident: CInt, _ events: CInt, _ callback: (@convention(c) (CInt, CInt, UnsafeMutableRawPointer?) -> CInt)?, _ data: UnsafeMutableRawPointer?) -> CInt

// Android Looper callback: drain the Swift main queue whenever its port signals.
private func drainMainQueueCallback(_ fd: CInt, _ events: CInt, _ data: UnsafeMutableRawPointer?) -> CInt {
    _dispatch_main_queue_callback_4CF()
    return 1 // keep the fd registered
}

// Wires the Swift main DispatchQueue into THIS thread's Android Looper, so MainActor / main-queue
// work scheduled by the Swift Testing run actually drains. Must run ON THE MAIN THREAD (which owns the
// Android main Looper). Without this the swt run hangs after `testStarted`. This mirrors what
// `AndroidLooper.installGlobalExecutor()` does in a real Fuse app, but implemented directly against the
// NDK ALooper + libdispatch to avoid pulling CoreFoundation into the standalone harness library.
@_cdecl("Java_\(testFullClass.replacingOccurrences(of: ".", with: "_"))_setupMainLooper")
func setupMainLooper(_ env: JNIEnvironment, _ thisObj: jobject) -> jboolean {
    guard let looper = ALooper_forThread() else {
        androidLog(ANDROID_LOG_ERROR, "SwiftTest", "setupMainLooper: no Android Looper on this thread")
        return jboolean(0)
    }
    ALooper_acquire(looper)
    let dispatchPort = _dispatch_get_main_queue_port_4CF()
    let result = ALooper_addFd(looper, dispatchPort, 0, CInt(ALOOPER_EVENT_INPUT), drainMainQueueCallback, nil)
    androidLog(ANDROID_LOG_INFO, "SwiftTest", "setupMainLooper addFd -> \\(result)")
    return result == 1 ? jboolean(1) : jboolean(0)
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

    // dlopen() does NOT invoke JNI_OnLoad (only System.loadLibrary does), so the Skip bridge's
    // JNI.jni global stays unset and the first bridged call (e.g. AndroidBundle.main) traps with
    // "JNI.jni was unset". We must manually invoke the BRIDGE's JNI_OnLoad with the cached JavaVM.
    //
    // We dlopen libSkipBridge.so explicitly and resolve JNI_OnLoad from THAT handle, rather than
    // dlsym(testBundleHandle, "JNI_OnLoad"): the harness shim itself exports a global JNI_OnLoad
    // (System.loadLibrary loads it RTLD_GLOBAL) that only sets g_jvm, and a handle-relative lookup
    // can resolve the harness's symbol instead of the bridge's. Both return JNI_VERSION_1_6, so the
    // wrong one silently leaves JNI.jni unset. Resolving from the libSkipBridge.so handle gets its own.
    if let bridgeHandle = dlopen("libSkipBridge.so", RTLD_NOW) {
        if let onLoadSym = dlsym(bridgeHandle, "JNI_OnLoad") {
            typealias JNIOnLoadFn = @convention(c) (UnsafeMutablePointer<JavaVM?>?, UnsafeMutableRawPointer?) -> jint
            let jniOnLoad = unsafeBitCast(onLoadSym, to: JNIOnLoadFn.self)
            let version = jniOnLoad(g_jvm, nil)
            androidLog(ANDROID_LOG_INFO, "SwiftTest", "invoked libSkipBridge JNI_OnLoad -> \\(version)")
        } else {
            androidLog(ANDROID_LOG_ERROR, "SwiftTest", "libSkipBridge.so has no JNI_OnLoad symbol")
        }
    } else {
        let err = dlerror().flatMap({ String(cString: $0) }) ?? ""
        androidLog(ANDROID_LOG_ERROR, "SwiftTest", "could not dlopen libSkipBridge.so: \\(err)")
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

// MARK: - Conventional `mode: native` test module (Robolectric / host JVM, no device) generation

/// Package.swift for the *host* (Robolectric) Swift test harness package. Unlike the Android harness it
/// links nothing Android-specific (no `liblog`/`libandroid`), so it builds for the host platform.
let hostHarnessPackageSwift: String = """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "test-harness",
    platforms: [ .macOS(.v13) ],
    products: [
        .library(name: "\(testHarnessLib)", type: .dynamic, targets: ["TestHarness"])
    ],
    targets: [
        .target(name: "TestHarness")
    ]
)
"""

/// Swift source for the *host* test harness used by Robolectric (`testDebug`, no device). It is pure Swift
/// with raw-pointer JNI (the ABI passes opaque pointers, so no JNI headers / `import Android` are needed)
/// and NO Android NDK / ALooper: the JVM-hosted Swift runtime relaxes the MainActor assertion, so no main
/// queue drain is required, and the Swift Testing `Task` schedules because this is a separate `.dynamic`
/// library (the version-scripted `--build-tests` bundle has no concurrency workers, so an in-bundle Task
/// would never run). It `dlopen`s the test bundle + `libSkipBridge` (to set `JNI.jni`), runs the swt
/// ABI-v0 entry point, and returns 0/1; per-event JSON records go to stderr (captured by Gradle).
func hostTestHarnessSwiftSource(testLibName: String) -> String {
    return """
import Dispatch
#if canImport(Darwin)
import Darwin
private let dylibSuffix = "dylib"
#elseif canImport(Glibc)
import Glibc
private let dylibSuffix = "so"
#endif

nonisolated(unsafe) var g_jvm: UnsafeMutableRawPointer? = nil

@_cdecl("JNI_OnLoad")
public func JNI_OnLoad(_ vm: UnsafeMutableRawPointer?, _ reserved: UnsafeMutableRawPointer?) -> Int32 {
    g_jvm = vm
    return 0x00010006 // JNI_VERSION_1_6
}

@_cdecl("Java_\(testFullClass.replacingOccurrences(of: ".", with: "_"))_setupMainLooper")
public func setupMainLooper(_ env: UnsafeMutableRawPointer?, _ thisObj: UnsafeMutableRawPointer?) -> UInt8 {
    return 1 // no-op on the host JVM (no Android Looper; MainActor assertion is relaxed in JVM-hosted mode)
}

private typealias EntryPoint = @convention(thin) @Sendable (
    _ configurationJSON: UnsafeRawBufferPointer?,
    _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
) async throws -> Bool

@_cdecl("Java_\(testFullClass.replacingOccurrences(of: ".", with: "_"))_runTests")
public func runTests(_ env: UnsafeMutableRawPointer?, _ thisObj: UnsafeMutableRawPointer?) -> Int32 {
    // RTLD_GLOBAL so the statically-linked module's bridged Java_* symbols are JVM-resolvable.
    guard let handle = dlopen("\(testLibName).\\(dylibSuffix)", RTLD_NOW | RTLD_GLOBAL) else {
        fputs("HostTestHarness: dlopen \(testLibName).\\(dylibSuffix) failed: \\(dlerror().flatMap { String(cString: $0) } ?? "")\\n", stderr)
        return 1
    }
    // dlopen does not invoke JNI_OnLoad; set the Skip bridge's JNI.jni by invoking libSkipBridge's JNI_OnLoad.
    if let h = dlopen("libSkipBridge.\\(dylibSuffix)", RTLD_NOW), let sym = dlsym(h, "JNI_OnLoad") {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
        _ = unsafeBitCast(sym, to: Fn.self)(g_jvm, nil)
    }
    guard let sym = dlsym(handle, "swt_abiv0_getEntryPoint") else {
        fputs("HostTestHarness: swt_abiv0_getEntryPoint not found\\n", stderr)
        return 1
    }
    typealias GetEntryPointFn = @convention(c) () -> UnsafeRawPointer?
    guard let raw = unsafeBitCast(sym, to: GetEntryPointFn.self)() else { return 1 }
    let entryPoint = unsafeBitCast(raw, to: EntryPoint.self)
    // If SKIP_SWT_EVENTS is set (by the Gradle test block), persist the raw swt ABI-v0 JSON event stream
    // (one record per line) so `skip test` can recover per-test results and report them individually
    // instead of the single aggregate. fputs locks the FILE internally, so concurrent records are safe.
    nonisolated(unsafe) let eventsFile: UnsafeMutablePointer<FILE>? = getenv("SKIP_SWT_EVENTS").flatMap { fopen($0, "w") }
    let recordHandler: @Sendable (UnsafeRawBufferPointer) -> Void = { rec in
        guard let base = rec.baseAddress, rec.count > 0 else { return }
        let json = String(decoding: UnsafeBufferPointer(start: base.assumingMemoryBound(to: UInt8.self), count: rec.count), as: UTF8.self)
        if let eventsFile { fputs(json + "\\n", eventsFile); fflush(eventsFile) }
        fputs("SwiftTest: " + json + "\\n", stderr)
    }
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var success = false
    Task {
        defer { semaphore.signal() }
        success = (try? await entryPoint(nil, recordHandler)) ?? false
    }
    semaphore.wait()
    if let eventsFile { fclose(eventsFile) }
    return success ? 0 : 1
}
"""
}

/// Kotlin source for the Robolectric (host JVM) test generated into a `mode: native` test module's
/// `src/test/kotlin/org/swift/test/SwiftTestRunner.kt`. Loads the host harness dylib (from the
/// `skip.test.libs` system property set by the Gradle block), caches the Robolectric `Context` for the
/// swt cooperative threads, and asserts the suite passes — so `testDebug` (no device) yields a JUnit result.
let robolectricTestRunnerKotlinSource: String = """
// Auto-generated by Skip — do not edit
package \(testPackage)

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.runner.RunWith

@RunWith(org.robolectric.RobolectricTestRunner::class)
class \(testClassName) {
    private external fun runTests(): Int

    @Test fun nativeSwiftTests() {
        val libs = System.getProperty("skip.test.libs") ?: error("skip.test.libs not set (buildLocalSwiftTestLibs did not run)")
        System.load(libs + "/" + System.mapLibraryName("\(testHarnessLib)"))
        // Cache the Robolectric Context so the native swt threads can resolve it. launch() sets the
        // launch context before the (host-unavailable) initBridge call, so catch and continue.
        val ctx = ApplicationProvider.getApplicationContext<Context>()
        try { skip.foundation.ProcessInfo.launch(ctx) } catch (e: Throwable) { }
        assertEquals("native Swift Testing cases should all pass", 0, runTests())
    }
}
"""

/// Gradle DSL appended to a `mode: native` test module's under-test `build.gradle.kts` for the Robolectric
/// (`testDebug`, no device) path. Registers `buildLocalSwiftTestLibs` (runs `skip android test
/// --build-test-libs --robolectric`, building the host test bundle + `libtest_harness` + Swift-runtime/
/// bridge dylibs into `<build>/test-jni-libs-host` and writing a `dyld-env.txt`), then makes every `Test`
/// task depend on it, point `skip.test.libs` at that dir, and apply the staged `DYLD_*`/`LD_LIBRARY_PATH`
/// values (so `Testing.framework` + the Swift runtime resolve when the harness `dlopen`s the test bundle).
let nativeTestRobolectricGradleBlock: String = """
// Native Swift Testing (`mode: native`) Robolectric (host JVM, no device) support generated by Skip
tasks.register("buildLocalSwiftTestLibs") {
    doLast {
        project.objects.newInstance<SkipBridgeExecOps>().execOps.exec {
            workingDir(layout.projectDirectory)
            commandLine("sh", "-cx", "\\"${skipcmd}\\" android test --build-test-libs \\"${swiftBuildFolder()}/test-jni-libs-host\\" --robolectric --package-path \\"${swiftSourceFolder()}\\" --configuration debug --scratch-path \\"${swiftBuildFolder()}/swift-test-host\\"")
            environment("SKIP_BRIDGE", "1")
            if (file(skipCommand).exists()) { environment("SKIP_COMMAND_OVERRIDE", skipCommand) }
        }
    }
}

tasks.withType<Test>().configureEach {
    val libsDir = "${swiftBuildFolder()}/test-jni-libs-host"
    if (System.getenv("SKIP_BRIDGE_ROBOLECTRIC_BUILD_DISABLED") != "1") {
        dependsOn("buildLocalSwiftTestLibs")
    }
    systemProperty("skip.test.libs", libsDir)
    doFirst {
        // buildLocalSwiftTestLibs writes the dynamic-loader env (Testing.framework + Swift runtime paths)
        // it resolved on the host; apply them to the forked test JVM before it loads the harness.
        val dyldEnv = file(libsDir + "/dyld-env.txt")
        if (dyldEnv.exists()) {
            dyldEnv.readLines().forEach { line ->
                val eq = line.indexOf('=')
                if (eq > 0) { environment(line.substring(0, eq), line.substring(eq + 1)) }
            }
        }
        // Have the native harness write the swt event stream into the junit output dir, so `skip test`
        // can recover per-test results (otherwise only the aggregate SwiftTestRunner case is reported).
        val eventsDir = reports.junitXml.outputLocation.get().asFile
        eventsDir.mkdirs()
        environment("SKIP_SWT_EVENTS", eventsDir.resolve("swt-events.jsonl").absolutePath)
    }
}
"""
