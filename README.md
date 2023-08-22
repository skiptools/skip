# Skip

Skip brings iPhone apps to Android by transpiling Swift source code into Kotlin and SwiftPM packages into Gradle projects.

## Intro

A Skip project is a standard Swift Package Manager (SwiftPM) project that uses the [Skip](https://skip.tools) plugin to transpile the Swift target modules into a Kotlin Gradle project. It uses the various compatibility frameworks (skip-lib, skip-unit, skip-foundation, and skip-ui) to provide Kotlin-side APIs that are compatible with the Swift standard library, the XCUnit testing framework, the Core Foundation libraries, and SwiftUI.

Skip is distributed both as a standard SwiftPM build tool plugin, as well as a command-line "skip" tool for creating, managing, testing, and packaging Skip projects.

### Installing Skip

The `skip` command-line tool is used to create, manage, build, test, and package dual-platform Skip libraries apps. The following instructions assume familiarity with using Terminal.app on macOS and basic UNIX commands.

On macOS 13.5+ with [Homebrew](https://brew.sh) and [Xcode](https://developer.apple.com/xcode/) installed, Skip can be installed with this command: 

```shell
brew install skiptools/skip/skip
```

This will download and install the `skip` tool itself, as well as the `gradle` and `openjdk` dependencies that are necessary for building and testing the Kotlin/Android side of the app.

Once installed, you can use `skip doctor` to do a system checkup, which will check for the latest updates and identify any missing or out-of-date dependencies:

```
skip doctor

Skip Doctor
[✓] Checking Skip: 0.5.96
[✓] Checking Swift: 5.9
[✓] Checking Xcode: 15.0
[✓] Checking Gradle: 8.2.1
[✓] Checking Java: 20.0.1
[✓] Checking Android Studio: 2022.3
[✓] Skip Updates: 0.5.96
Skip (0.5.96) checks complete
```

**Note**: Android Studio is not needed for building and testing Skip projects. It is only needed for launching a transpiled project in the Android Emulator. It can be installed with `brew install --cask android-studio` or [downloaded directly](https://developer.android.com/studio).

## Creating a new App project

Create and build a new project with the command:

```shell
skip create myapp
```

This will create the folder "myapp" containing a new dual-platform Skip project and run an initial build of the app[^1].

Once the project has been successfully created in the "myapp" folder, the `myapp/App.xcodeproj` file can be opened in Xcode.app from the Finder, or with the command:

```shell
xed myapp/App.xcodeproj
```

This project contains an iOS "App" target, along with an "AppDroid" target that will transpile, build, and launch the app in an Android emulator (which must be launched separately from the "Device Manager" of [Android Studio.app](https://developer.android.com/studio)).


## Creating a new Library project



[^1]: The initial build may take a long time due to Gradle downloading the necessary Android and Jetpack Compose dependencies (approx. 1G) to the `~/.gradle` folder.
