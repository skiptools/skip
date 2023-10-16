# Skip

Skip is a technology for creating dual-platform mobile apps in SwiftUI for both iOS and Android. It consists of two halves:

* **skipstone**: a plugin for Xcode that transpiles Swift source code into Kotlin source code, and SwiftPM projects into Gradle projects
* **skipstack**: a free and open-source stack of modules that bridges the Foundation and SwiftUI APIs for iOS into their equivalent Kotlin and Compose APIs for Android

Skip facilitates the creation of dual-platform apps for both iPhone and Android devices by transpiling Swift Package Manager modules into equivalent Gradle projects and Kotlin source code. A single user-interface toolkit (SwiftUI), in a single language (Swift), can be used to create genuinely native apps for both iOS and Android:

![Screenshot](https://assets.skip.tools/skipdev.png)

Skip is a work in progress, and currently handles only a subset of the SwiftUI and Foundation APIs. An introductory video can be seen [here](https://www.youtube.com/watch?v=8u4KWvsfOtk), and a showcase of the available components can be previewed [here](https://source.skip.tools/skipapp-playground).  Experimentation with this early technology is welcome – we have forums for both general [discussions](https://source.skip.tools/skip/discussions) as well as specific [issues and bug reports](https://source.skip.tools/skip/issues).

## Getting Started

Skip requires a macOS 14 development machine with [Xcode 15](https://developer.apple.com/xcode), [Android Studio 2023](https://developer.android.com/studio), and [Homebrew](https://brew.sh) installed. Install Skip by running the Terminal command:

```
brew install skiptools/skip/skip
```

Ensure that the development prerequisites are satisfied by running:

```
skip checkup
```

If the checkup passes, create a new app project with the command:

```
skip init --open-xcode --appid=bundle.id project-name HelloSkip
```

This will create a `project-name/` folder with a new SwiftPM package containing a single module named `HelloSkip`, along with a `HelloSkip.xcodeproj` project with a `HelloSkipApp` target and an `.xcconfig` file specifying the app's name, bundle identifier, and other customizable metadata.

Xcode will open the new project, but before the transpiled app can be built and launched, an Android emulator needs to be running. Launch `Android Studio.app` and open the `Virtual Device Manager` from the ellipsis menu of the "Welcome" dialog. From there, "Create Device" (e.g., "Pixel 6") and then "Launch" the emulator.

Once the Android emulator is running, select and run the `HelloSkipApp` target in Xcode. You may be prompted with a dialog to affirm that you trust the Skip plugin. Once the build and run action completes, the SwiftUI app will open in the selected iOS simulator, and at the same time the transpiled app will launch in the currently-running Android emulator.

Browse to the `ContentView.swift` file and make a small change and re-run the target: the app will be re-built and re-run on both platforms simultaneously with your changes.

See the Skip product [documentation](https://skip.tools/docs) for further information on the tools and available modules. Happy Skipping!

## Development Tips

- *Stay on the happy path*. Many Foundation and SwiftUI APIs are working in Skip, but many more are still works in progress. Use known working components and APIs as previewed in the sample [Playground](https://source.skip.tools/skipapp-playground) and [Weather](https://source.skip.tools/skipapp-weather) apps. Anything **not** shown in the screenshots for those app is likely to **not** be working yet, but experimentation and iteration is the best way to explore the ever-expanding boundaries of the `SkipUI` and `SkipFoundation` modules.
- *Re-run frequently*. For app projects, re-run the app on both platforms constantly. Skip's transpiler is designed to accommodate incremental development and enable the re-launching of an app on both iOS simulator and Android emulator in mere seconds. Only by re-running the frequently will you be able to quickly identify and resolve platform-specific issues and API limitations before they accumulate.
- *Modularize your projects*. Skip is designed to accommodate and encourage using multi-module projects. The default `skip init` command creates a single-module app for simplicity, but a modularized project can be created by specifying additional module names at the end of the chain. For example: `skip init --open-xcode --appid=bundle.id multi-project HelloSkip HelloModel HelloCore` will create a SwiftPM project with three modules: `HelloSkip`, `HelloModel`, and `HelloCore`. The heuristics of such module creation is that the modules will all be dependent on their subsequent peer module, with the initial module having an initial dependency on `SkipUI`, the second module depending on `SkipModel`, and the final module in the chain depending on `SkipFoundation`. The `Package.swift` file can be manually edited to shuffle around dependencies, or add new dependencies on external Skip frameworks such as [SkipSQL](https://source.skip.tools/skip-sql) or [SkipXML](https://source.skip.tools/skip-xml).
- *Re-test frequently*. The `skip init` command creates `Test/` modules for each of the `Sources/` modules that it creates. When run agains the macOS target in Xcode, or when run from the command-line with `swift test` or `skip test`, the source and XCUnit tests will be automatically transpiled into equivalent Kotlin JUnit tests, and the tests will be run both on the macOS platform for the Swift code, and on the simulated "Robolectric" Android environment using the local Gradle and JVM. This is called `test parity`, and is a critical component to ensuring that your code runs in exactly the same way in Swift as in Kotlin. Dividing up your app into separately-testable component modules makes it easier to iterate on the build-and-test cycle for that part of an app.
- *Use the `.xcconfig` file*. App customization should be primarily done by directly editing the `.xcconfig` file, rather than changing the app's setting. Only properties that are set the `.xcconfig` file, such as `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER` and `MARKETING_VERSION`, will carry-through to the `AndroidManifest.xml`. This is how a subset of the app's metadata can be kept in sync between the iOS and Android versions, but it requires that the properties not be changed using the Xcode Build Settings interface (which does not modify the `.xcconfig` file, but instead overrides the settings in the local `.xcodeproj/` folder. 
- *Run on an Android Emulator*. An new emulator can be setup by launching `Android Studio.app`, opening the `Device Manager` from the ellipsis menu of the Welcome screen, and then setting up an emulator. Exactly one emulator must be running in order for the Skip projects `Launch APK` script phase to install and run the app successfully. Once an emulator has been setup, it can be launched in the future without using `Android Studio.app` with the terminal command: `~/Library/Android/sdk/emulator/emulator @Pixel_6_API_33`.
- *Run on an Android Device*. To run on a device rather than the emulator, pair the Android device with your development machine and set the `ANDROID_SERIAL` variable in the project's `.xcconfig` file to the device's identifier. Running the `/opt/homebrew/bin/adb devices` command will show the available paired identifiers. Setting the `ANDROID_SERIAL` is also the only way to run the app when there are multiple emulators running.
- *Debug*. Debugging the Swift side of the app just uses Xcode's built-in debugging tools. For debugging the Android side of the app, you will need to run the app directly from `Android Studio.app` in order to set breakpoints and use features of the IDE's debugger. The transpiled Skip project can be opened by expanding the `Skip` folder in Xcode and browsing to the `settings.gradle.kts` file in the transpiled app module. The `File` → `Open with External Editor` menu will then launch the project in `Android Studio.app` (or any other IDE that is configured to handle Gradle build files). From there, the project can be launched on an emulator or device and the native debugging tools can be used.
- *Logs*. The Kotlin implementation of `OSLog.Logger` in SkipFoundation forwards log messages to `logcat`, which is Android's native logging equivalent. When logging messages in an app, the `OSLog` messages from the swift side of the app will appear in Xcode's console as usual. The the Android side, using the `logcat` tab from Android Studio is a good way to browse and filter the app's log messages. This can also be done from the terminal, using the command `adb logcat`, which has a variety of filtering flags that can applied to the default (verbose) output.

## Gotchas

- **Missing/unimplemented APIs**: The skipstack core modules `SkipFoundation` and `SkipUI` implement many, but not all, of their equivalent APIs in `Foundation` and `SwiftUI`. Missing APIs will typically only be identified when running or testing the Skip app (which is one reason to run or test frequently). For "known-unknowns" (much of SkipUI), the APIs are marked as `@unavailable`, and Xcode will present a nice error. For the "unknown-unknowns" (much of SkipFoundation), the only indication will be a failure to compile the Kotlin when the app is launched or the module is tested.
- **macOS is not iOS**: While it is possible to run the unit tests for the various modules in a Skip package against the iOS destination, doing so will not run the transpiled tests against Android. This is because the testing process relies on running the (generated) `XCSkipTests.swift` test, which forks the Gradle process on macOS and interprets the JUnit test results. What is means is that your Swift code needs to run on both iOS and macOS, and while many of the Foundation and SwiftUI APIs are identical on both these platforms, 
- **Robolectric is not Android**: Similar to the macOS/iOS issue, the local Robolectric testing environment is similar, but not identical, to an actual Android emulator or device. Some Android APIs are missing from Robolectric, and it is possible that the compiled Java bytecode run locally differs from the Dalvik/ART byte code that is run in a true Android environment.
- **Garbage Collection**: Skip transpiles non-garbage-collected Swift into garbage-collected Kotlin. This changes the potential lifespan for the transpiled types. Classes that that rely on `deinit` to clean up resources should be aware that such cleanup will be delayed until GC happens in the Kotlin environment.
- **32-bit Ints**. Skip transpiles Swift's platform-dependent `Int` types into Kotlin's `Int` type, which on the JVM is a 32-bit integer. Declaring types explicitly as `Int64` is recommended for integer types as risk of overflowing the 32-bit range (which, in Java, does not cause an error condition like in Swift, but instead silents wraps `Int.max` around to `Int.min`, making such issues a potential cause of hidden bugs).
- **Numeric Literals**. An Swift integer literal is transpiled into a Kotlin 32-bit integer, and a decimal literal will transpile into a Kotlin double-precision floating point type. Skip performs no other numeric type coercion, so for other types, they must be specified explicitly, such as `Int16(12)`, `Float(12.12)`, and `UInt64(9_999)`.

## Troubleshooting

This section lists known issues with the `skip` tool and associated Xcode plugins.

Skip's architecture relies on recent advances in the plugin system used by Xcode 15 and Swift Package Manager 5.9. When unexpected issues arise, often the best first step is to clean your Xcode build (`Product` → `Clean Build Folder`) and reset packages (`File` → `Packages` → `Reset Package Caches`). Restarting Xcode is sometimes warranted, and trashing the local `DerivedData/` folder might even be needed. Less extreme solutions for commonly known error conditions are listed below, and search the [documentation](https://skip.tools/docs), [issues](https://source.skip.tools/skip/issues), and [discussions](https://source.skip.tools/skip/discussions) for more information and to report problems.

- Xcode sometimes reports error messages like the following:

    ```shell
    Internal inconsistency error (didStartTask): targetID (174) not found in _activeTargets.
    Internal inconsistency error (didEndTask): '12' missing from _activeTasks.
    ```

    When these errors occur, the build appears to complete successfully although changes are not applied. Unfortunately, this is an Xcode bug. We have found the following workarounds:

    - Continue to retry the build. Eventually Xcode will complete successfully, although the errors may continue to become more frequest until you are foced to apply one of the other solutions below.
    - Restart Xcode.
    - Clean and rebuild.

    You can read more about this Xcode error on the [Swift.org forums](https://forums.swift.org/t/internal-inconsistency-error-didstarttask/61194).
- Skip may highlight the wrong line in build errors. When Skip surfaces the wrong line number, it is typically only one line off.


## Customizing Kotlin
- #if SKIP blocks
- // SKIP INSERT statements
- Including raw Kotlin files in the module's Skip/ folder 



