# Native Swift Testing regressions

The shared Swift Testing fixture covers a MainActor test, a MainActor suite
initializer, suspension and resumption, a worker-to-main-actor hop, and a
DispatchQueue.main callback. It checks both actor isolation and main-thread
execution without Skip dependencies or platform conditionals.

From the repository root:

```sh
git submodule update --init
swift build --product SkipRunner
swift test --package-path IntegrationTests/MainActor
.build/debug/SkipRunner android test --apk --testing-library testing \
  --package-path IntegrationTests/MainActor --android-serial emulator-5554
```

Use a Swift Android SDK matching the native compiler. Pass `--toolchain`,
`--swift-version`, and `--sdk` when the defaults do not select that combination.
Keep the toolchain, SDK, fixture and device identical when comparing revisions.
The original 1.9.19 harness traps in `_dispatch_main_queue_callback_4CF`; the
fixed harness must finish all three tests and return successful instrumentation.

CoreFoundation initializes libdispatch on the thread that loads it. Both
instrumentation entry points therefore load the harness and create its main run
loop on Android's main thread, before starting the test worker. The Android
Looper watches the dispatch port and services it through CFRunLoop. Regenerate
the harness with the local CLI; do not edit generated Java, Kotlin or Swift.

## Bridged test modules

Bare `skip android test --apk` packages native libraries without Kotlin bridge
classes or assets. Use the generated Gradle test module for bridged suites:

- Add the `SkipTest` product and `skipstone` plugin to the test target.
- Declare `skip.mode: native` in that target's `Skip/skip.yml`.
- Run its generated `connectedDebugAndroidTest` task.

The runner initializes `ProcessInfo` with the Android target context and loads
bridge modules declared by the merged manifest. The test-library task builds
`src/test/swift`, rather than the component package at `src/main/swift`.

This harness fix does not change package-root discovery or source enumeration.
The standalone fixture above and conventional `Sources/<Target>` and
`Tests/<TargetTests>` layouts do not require those changes. Custom target paths
and nested test packages may need separate package-mirroring fixes.

The source scanner currently walks the target directory even for files excluded
by SwiftPM. Keep Apple-only rendering fixtures outside that directory when
validating a separate Android logic package. This harness change does not alter
source exclusion behavior. Relative local package dependencies must also have
an explicit package name so the existing manifest mirror can identify them.

## Missing bridge prerequisite

The harness checks for `skip/bridge/BridgeSupportKt` before installing SkipBridge's
exception converter. Without that class, converting the initial class-lookup
exception can recursively wait on the same initializer. The runner must instead
fail with an actionable diagnostic before any Swift Testing event.

`MissingBridge/SwiftTestRunner.java` exercises this boundary as a command-line
JNI driver. Compile it with `javac` and Android's `d8`. Stage its `classes.dex`,
the generated MainActor fixture libraries, and `libSkipBridge.so` with all its
native dependencies in a temporary device directory. Exclude the Skip Kotlin
classes, then run:

```sh
adb shell 'CLASSPATH=/data/local/tmp/bridge-probe/classes.dex \
  LD_LIBRARY_PATH=/data/local/tmp/bridge-probe/lib timeout 20s \
  app_process /system/bin org.swift.test.SwiftTestRunner \
  /data/local/tmp/bridge-probe/lib/libtest_harness.so'
```

The driver requires the diagnostic and fails if the harness starts tests or
returns normally. A missing transitive native library is a different failure
and does not validate this check.

For end-to-end validation, run an unchanged bridged suite through bare `--apk`
and require that diagnostic with a nonzero result before tests start. Then run
it through its native Gradle test module and require every Swift test to finish.
The prerequisite failure is not evidence that the suite itself passes.
