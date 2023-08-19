# Skip

The `skip` tool is used to create, manage, build, test, and package dual-platform Skip apps.

## Installing

On macOS 13.5+ with [homebrew](https://brew.sh) and [Xcode](https://developer.apple.com/xcode/) installed, Skip can be installed with this command: 

```shell
brew install skiptools/skip/skip
```

This will download and install the `skip` tool itself, as well as the `gradle` and `openjdk` dependencies that are necessary for building and testing the Android side of the app.

Once installed, create and build a new project with the command:

```shell
skip create myapp
```

This will create the folder "myapp" containing a new dual-platform Skip project and run an initial build of the app[^1].

Once the project has been successfully created in the "myapp" folder, the `myapp/App.xcodeproj` file can be opened in Xcode.app from the Finder, or with the command:

```shell
xed myapp/App.xcodeproj
```

This project contains an iOS "App" target, along with an "AppDroid" target that will transpile, build, and launch the app in an Android emulator (which must be launched separately from the "Device Manager" of [Android Studio.app](https://developer.android.com/studio)).



[^1] The initial build may take a long time due to Gradle downloading the necessary Android and Jetpack Compose dependencies (approx. 1G) to the `~/.gradle` folder.
