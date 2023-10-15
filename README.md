# Skip

Skip is a technology for creating dual-platform mobile apps in SwiftUI for both iOS and Android. It consists of two halves:

* **skipstone**: a plugin for Xcode that transpiles Swift source code into Kotlin source code, and SwiftPM projects into Gradle projects
* **skipstack**: a free and open-source stack of modules that bridges the Foundation and SwiftUI APIs for iOS into their equivalent Kotlin and Compose APIs for Android

Skip facilitates the creation of dual-platform apps for both iPhone and Android devices by transpiling Swift Package Manager modules into equivalent Gradle projects and Kotlin source code. A single project, in a single language (Swift), can be used to create genuinely native Android and iOS apps.

Skip is a work in progress, and currently handles only a subset of the SwiftUI and Foundation APIs. An introductory video can be seen [here](https://www.youtube.com/watch?v=8u4KWvsfOtk), and a showcase of the available components can be previewed [here](https://source.skip.tools/skipapp-playground).  Experimentation with this early technology is welcome – we have forums for both general [discussions](https://source.skip.tools/skip/discussions) as well as specific [issues and bug reports](https://source.skip.tools/skip/issues).

## Installation

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

This will create a `project-name/` folder and open the new project in Xcode.

Before the transpiled app can be run, an Android emulator need to be run from `Android Studio.app` by opening the `Virtual Device Manager` from the ellipsis menu of the "Welcome" dialog. From there, "Create Device" (e.g., "Pixel 6") and then "Launch" the emulator. 

Once an Android emulator is running, select and run the `HelloSkipApp` target in Xcode. The SwiftUI app will open in the selected iOS simulator, and at the same time the transpiled app will launch in the currently-running Android emulator. Open the `ContentView.swift` file and make a change and re-run: the app will be re-built and re-run on both platforms simultaneously with your changes. This is the way.

See the Skip product [documentation](https://skip.tools/docs) for further information on the tools and available modules.

## Known Issues

This section lists known issues with the `skip` tool and associated Xcode plugins.

Skip's architecture relies on recent advances in Xcode and Swift Package Manager. When unexpected issues arise, often the best first step is to clean your Xcode build (Product -> Clean Build Folder) and reset packages (File -> Packages -> Reset Package Caches), 

Common known error conditions are listed below. See the [issues](https://source.skip.tools/skip/issues) list for more details.

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
