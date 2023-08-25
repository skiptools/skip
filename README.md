# Skip

Skip brings iPhone apps to Android by transpiling Swift source code into Kotlin and converting Swift packages into Gradle projects. Skip translates SwiftUI into Jetpack Compose, which provides a modern declarative toolkit for developers and results in a genuinely native end-user experience.
## Intro

A Skip project is a SwiftPM package that uses the Skip plugin to transpile the Swift target modules into a Kotlin Gradle project. Skip compatibility frameworks provide Kotlin-side APIs for parity with the Swift standard library ([skip-lib](https://source.skip.tools/skip-lib)), the XCTest testing framework ([skip-unit](https://source.skip.tools/skip-unit)), the Foundation libraries ([skip-foundation](https://source.skip.tools/skip-foundation)), and the SwiftUI ([skip-ui](https://source.skip.tools/skip-ui)) user-interface toolkit.

Skip is distributed both as a standard SwiftPM build tool plugin, as well as a command-line "skip" tool for creating, managing, testing, and packaging Skip projects.

### Installing Skip

The `skip` command-line tool is used to create, manage, build, test, and package dual-platform Skip apps. The following instructions assume familiarity with using Terminal.app on macOS.

On macOS 13.5+ with [Homebrew](https://brew.sh) and [Xcode](https://developer.apple.com/xcode/) installed, Skip can be installed with the command: 

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

Skip library projects are pure SwiftPM packages that encapsulate common functionality. Each of the core Skip compatibility frameworks ([skip-lib](https://source.skip.tools/skip-lib), [skip-unit](https://source.skip.tools/skip-unit), [skip-foundation](https://source.skip.tools/skip-foundation), and [skip-ui](https://source.skip.tools/skip-ui)) are Skip library projects. Other commonly-used projects include [skip-sql](https://source.skip.tools/skip-sql), [skip-script](https://source.skip.tools/skip-script), and [skip-zip](https://source.skip.tools/skip-zip).

A new library can be created and opened with:

```shell
skip init --build --test lib-name ModuleName
```

This will create a new `lib-name` folder containing a `Package.swift` with targets of `ModuleName` and `ModuleNameTests`, as well the necessary peer Kotlin targets of `ModuleNameKt` and `ModuleNameKtTests`.

This project can be opened in Xcode.app, which you can use to build and run the unit tests. Running `swift build` and `swift test` from the Terminal can also be used for headless testing as part of a continuous integration process.

### Skip Project structure

```shell
lib-name
├── Package.resolved
├── Package.swift
├── README.md
├── Sources
│   ├── ModuleName
│   │   └── ModuleName.swift
│   └── ModuleNameKt
│       ├── ModuleNameBundle.swift
│       └── Skip
│           └── skip.yml
└── Tests
    ├── ModuleNameKtTests
    │   ├── ModuleNameKtTests.swift
    │   └── Skip
    │       └── skip.yml
    └── ModuleNameTests
        └── ModuleNameTests.swift

```

### Skip Package.swift structure

```swift
// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "lib-name",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
    products: [
        .library(name: "ModuleName", targets: ["ModuleName"]),
        .library(name: "ModuleNameKt", targets: ["ModuleNameKt"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "0.6.3"),
        .package(url: "https://source.skip.tools/skip-unit.git", from: "0.0.0"),
        .package(url: "https://source.skip.tools/skip-lib.git", from: "0.0.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0"),
    ],
    // Each pure Swift target "ModuleName"
    // must have a peer target "ModuleNameKt"
    // that contains the Skip/skip.yml configuration
    // and any custom Kotlin.
    targets: [
        .target(name: "ModuleName", plugins: [.plugin(name: "preflight", package: "skip")]),
        .testTarget(name: "ModuleNameTests", dependencies: ["ModuleName"], plugins: [.plugin(name: "preflight", package: "skip")]),

        .target(name: "ModuleNameKt", dependencies: [
            "ModuleName",
            .product(name: "SkipUnitKt", package: "skip-unit"),
            .product(name: "SkipLibKt", package: "skip-lib"),
            .product(name: "SkipFoundationKt", package: "skip-foundation"),
        ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
        .testTarget(name: "ModuleNameKtTests", dependencies: [
            "ModuleNameKt",
            .product(name: "SkipUnit", package: "skip-unit"),
        ], resources: [.process("Skip")], plugins: [.plugin(name: "transpile", package: "skip")]),
    ]
)
```

## Getting Help

For solutions to common issues, please search the [discussion forums](https://github.com/skiptools/skip/discussions) and check the [Skip documentation](https://skip.tools). For bug reports, use the [issue tracker](https://github.com/skiptools/skip/issues). You can also contact us directly at [skip@skip.tools](mailto:skip@skip.tools) or on Matrix at [#skip:gitter.im](https://app.gitter.im/#/room/#skip:gitter.im). Please include the output of the `skip doctor` command in any communication related to technical issues.


[^1]: Android Studio is not needed for building and testing Skip projects. It is only needed for launching a transpiled project in the Android Emulator. It can be installed with `brew install --cask android-studio` or downloaded directly from [https://developer.android.com/studio](https://developer.android.com/studio).

[^2]: The initial build may take a long time due to Gradle downloading the necessary Android and Jetpack Compose dependencies (approx. 1G) to the `~/.gradle` folder.

