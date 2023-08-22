# Skip

Skip brings iPhone apps to Android by transpiling Swift source code into Kotlin and converting Swift packages into Gradle projects. SwiftUI on iOS translates into Jetpack Compose on Android for a genuinely native app experience.

## Intro

A Skip project is a SwiftPM project that uses the Skip plugin to transpile the Swift target modules into a Kotlin Gradle project. Compatibility frameworks provide Kotlin-side APIs for parity with the Swift standard library ([skip-lib](https://source.skip.tools/skip-lib)), the XCTest testing framework ([skip-unit](https://source.skip.tools/skip-unit)), the Foundation libraries ([skip-foundation](https://source.skip.tools/skip-foundation)), and the SwiftUI ([skip-ui](https://source.skip.tools/skip-ui)) user-interface toolkit.

Skip is distributed both as a standard SwiftPM build tool plugin, as well as a command-line "skip" tool for creating, managing, testing, and packaging Skip projects.

### Installing Skip

The `skip` command-line tool is used to create, manage, build, test, and package dual-platform Skip apps. The following instructions assume familiarity with using Terminal.app on macOS and basic UNIX commands.

On macOS 13.5+ with [Homebrew](https://brew.sh) and [Xcode](https://developer.apple.com/xcode/) installed, Skip can be installed with this command: 

```shell
brew install skiptools/skip/skip
```

This will download and install the `skip` tool itself, as well as the `gradle` and `openjdk` dependencies that are necessary for building and testing the Kotlin/Android side of the app.

Once installed, you can use `skip doctor` to perform a system checkup, which will identify any missing or out-of-date dependencies[^1].

## Creating a new Skip App

A new dual-platform Skip app can be created and opened with the command:

```shell
skip create --open myapp
```

This will create the folder "myapp" containing a new Skip project and runs an initial build of the app[^2], and then opens the new `myapp/App.xcodeproj` project in Xcode. This project contains an iOS "App" target, along with an "AppDroid" target that will transpile, build, and launch the app in an Android emulator (which must be launched separately from the "Device Manager" of Android Studio[^1]).


## Creating a new Skip Library



[^1]: Android Studio is not needed for building and testing Skip projects. It is only needed for launching a transpiled project in the Android Emulator. It can be installed with `brew install --cask android-studio` or downloaded directly from [https://developer.android.com/studio](https://developer.android.com/studio).

[^2]: The initial build may take a long time due to Gradle downloading the necessary Android and Jetpack Compose dependencies (approx. 1G) to the `~/.gradle` folder.

