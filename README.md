# Skip

Skip is a technology for creating dual-platform mobile apps in SwiftUI for both iOS and Android. It consists of two halves:

- **skipstone**: a plugin for Xcode that transpiles Swift source code into Kotlin source code, and SwiftPM projects into Gradle projects.
- **skipstack**: a free and open-source stack of modules that bridges the Foundation and SwiftUI APIs for iOS into their equivalent Kotlin and Compose APIs for Android.

With Skip, a single project, in a single language (Swift), can be used to create genuinely native apps for both Android and iOS.

Skip is a work in progress, and it currently handles only a subset of the SwiftUI and Foundation APIs. You can watch an introductory video [here](https://www.youtube.com/watch?v=8u4KWvsfOtk), and preview a showcase of the available components [here](https://source.skip.tools/skipapp-playground). Experimentation with this early technology is welcome – we have forums for both general [discussions](https://source.skip.tools/skip/discussions) as well as specific [issues and bug reports](https://source.skip.tools/skip/issues).

For more information on Skip, visit the [website](https://skip.tools) and read the [technical documentation](https://skip.tools/docs).

## Installation

Skip requires a macOS 14 development machine with [Xcode 15](https://developer.apple.com/xcode), [Android Studio 2023](https://developer.android.com/studio), and [Homebrew](https://brew.sh) installed. Install Skip by running the Terminal command:

```shell
brew install skiptools/skip/skip
```

Ensure that the development prerequisites are satisfied by running:

```shell
skip checkup
```

If the checkup passes, create a new app project with the command:

```shell
skip init --open-xcode --appid=bundle.id project-name AppName
```

This will create a `project-name/` folder and open the new project in Xcode. For example:

```shell
skip init --open-xcode --appid=com.xyz.HelloSkip hello-skip HelloSkip
```

Before you can build and run the transpiled app on Android, you must launch an Android emulator. You can launch an emulator from `Android Studio.app` by opening the `Virtual Device Manager` from the ellipsis menu of the "Welcome" dialog. From there, `Create Device` (e.g., "Pixel 6") and then `Launch` the emulator. 

Once the Android emulator is running, use Xcode to select your preferred iOS simulator and run the `<AppName>App` target. You may be prompted to affirm that you trust the Skip plugin. 

The first build will take some time as it compiles the *skipstack* open source libraries. Once the build and run action completes, your SwiftUI app will open in the selected iOS simulator, and at the same time the transpiled Android app will launch in the currently-running Android emulator. Browse to the `ContentView.swift` file in Xcode, make a change, and re-run the target: the app will be re-built and re-run on both platforms simultaneously with your changes.

See the Skip product [documentation](https://skip.tools/docs) for further information on the tools and available modules.

## Known Issues

This section lists known issues with the `skip` tool and associated Xcode plugin.

Skip relies on recent advances in Xcode's plugin system and Swift Package Manager. When unexpected issues arise, often the best first step is to clean your Xcode build (`Product` → `Clean Build Folder`) and reset packages (`File` → `Packages` → `Reset Package Caches`). Restarting Xcode is sometimes needed. 

Specific known error conditions are listed below. Search the [issues](https://source.skip.tools/skip/issues) for more information and to contribute.

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
