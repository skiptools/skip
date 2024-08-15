# Skip

Skip is a technology for creating dual-platform mobile apps in Swift. [Read this introduction](https://skip.tools/docs/) to learn more about Skip. 

This repository hosts the Skip development toolchain, a.k.a. SkipStone. It also hosts the Skip forums for general [discussions](http://community.skip.tools) as well as specific [issues and bug reports](https://source.skip.tools/skip/issues).

## Getting Started

### System Requirements

Skip requires a macOS 13 development machine with [Xcode 15](https://developer.apple.com/xcode), [Android Studio 2023](https://developer.android.com/studio), and [Homebrew](https://brew.sh) installed.

### Installation

Install Skip by running the Terminal command:

```shell
brew install skiptools/skip/skip
```

This will download and install the `skip` tool itself, as well as the `gradle` and JDK dependencies that are necessary for building and testing the Kotlin/Android side of your apps. Note: If you don't already have a compatible JDK+ installed on your machine, you may need to enter an administrator password to complete the installation.

Ensure that the development prerequisites are satisfied by running:

```plaintext
skip checkup
```

<img alt="Screenshot of terminal skip checkup command output" src="https://assets.skip.tools/intro/skip_checkup.png" style="width: 100%;" />


If the checkup passes, you're ready to start developing with Skip!

## Creating an App {#app_development}

Create a new app project with the command:

```plaintext
skip init --open-xcode --appid=bundle.id project-name AppName
```

For example:

```plaintext
skip init --open-xcode --appid=com.xyz.HelloSkip hello-skip HelloSkip
```

This will create a `hello-skip/` folder with a new SwiftPM package containing a single module named `HelloSkip`, along with folders named `Darwin` and `Android` and the shared `Skip.env` app configuration file. The `Darwin` folder will contain a `HelloSkip.xcodeproj` project with a `HelloSkip` target, which can be opened in Xcode.

Xcode will open the new project, but before you can build and launch the transpiled app, an Android emulator needs to be running. Launch `Android Studio.app` and open the `Virtual Device Manager` from the ellipsis menu of the Welcome dialog. From there, `Create Device` (e.g., "Pixel 6") and then `Launch` the emulator.

<img alt="Screenshot of the Android Studio Device Manager" src="https://assets.skip.tools/intro/device_manager.png" style="width: 100%;" />

Once the Android emulator is running, select and run the `HelloSkip` target in Xcode. The first build will take some time to compile the Skip libraries, and you may be prompted with a dialog to affirm that you trust the Skip plugin. Once the build and run action completes, the SwiftUI app will open in the selected iOS simulator, and at the same time the transpiled app will launch in the currently-running Android emulator.

<img alt="Screenshot of Skip running in both the iOS Simulator and Android Emulator" src="https://assets.skip.tools/intro/skip_xcode.png" style="width: 100%;" />

Browse to the `ContentView.swift` file and make a small change and re-run the target: the app will be re-built and re-run on both platforms simultaneously with your changes.

See the product [documentation](https://skip.tools/docs) for further information developing with Skip. Happy Skipping!


### Creating a Multi-Module App

Skip is designed to accommodate and encourage using multi-module projects. The default `skip init` command creates a single-module app for simplicity, but you can create a modularized project by specifying additional module names at the end of the chain. For example: 

```shell
skip init --open-xcode --appid=com.xyz.HelloSkip multi-project HelloSkip HelloModel HelloCore
```

This command will create a SwiftPM project with three modules: `HelloSkip`, `HelloModel`, and `HelloCore`. The heuristics of such module creation is that the modules will all be dependent on their subsequent peer module, with the first module (`HelloSkip`) having an initial dependency on `SkipUI`, the second module depending on `SkipModel`, and the final module in the chain depending on `SkipFoundation`. The `Package.swift` file can be manually edited to shuffle around dependencies, or to add new dependencies on external Skip frameworks such as the nascent [SkipSQL](https://source.skip.tools/skip-sql) or [SkipXML](https://source.skip.tools/skip-xml) libraries.

## Creating a Dual-Platform Framework {#framework_development}

Skip framework projects are pure SwiftPM packages that encapsulate common functionality. They are simpler than app projects, as they do not need `Darwin/` and `Android/` folders.

Each of the core Skip compatibility frameworks ([skip-lib](https://source.skip.tools/skip-lib), [skip-unit](https://source.skip.tools/skip-unit), [skip-foundation](https://source.skip.tools/skip-foundation), and [skip-ui](https://source.skip.tools/skip-ui)) are Skip framework projects. Other commonly-used projects include [skip-sql](https://source.skip.tools/skip-sql), [skip-script](https://source.skip.tools/skip-script), and [skip-zip](https://source.skip.tools/skip-zip).

A new framework project can be created and opened with:

```shell
skip init --build --test lib-name ModuleName
```

This will create a new `lib-name` folder containing a `Package.swift` with targets of `ModuleName` and `ModuleNameTests`.

This project can be opened in Xcode.app, which you can use to build and run the unit tests. Running `swift build` and `swift test` from the Terminal can also be used for headless testing as part of a continuous integration process.

### Skip Framework Structure

The structure of a Skip framework is exactly the same as any other SPM package:

```shell
lib-name
├── Package.resolved
├── Package.swift
├── README.md
├── Sources
│   └── ModuleName
│       ├── ModuleName.swift
│       ├── Resources
│       │   └── Localizable.xcstrings
│       └── Skip
│           └── skip.yml
└── Tests
    └── ModuleNameTests
        ├── ModuleNameTests.swift
        ├── Resources
        │   └── TestData.json
        ├── Skip
        │   └── skip.yml
        └── XCSkipTests.swift

```

Skip frameworks use a standard `Package.swift` file, with the exception of an added dependency on `skip` and use of the `skipstone` plugin for transpilation:

```swift
// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "lib-name",
    defaultLocalization: "en",
    platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
    products: [
        .library(name: "ModuleName", targets: ["ModuleName"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0"),
    ],
    targets: [
        .target(name: "ModuleName", plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "ModuleNameTests", dependencies: ["ModuleName"], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ]
)
```


## `skip init` Reference

```plaintext
zap /tmp % skip init --help
OVERVIEW: Initialize a new Skip project

USAGE: skip init [<options>] <project-name> <module-names> ...

ARGUMENTS:
  <project-name>          Project folder name
  <module-names>          The module name(s) to create

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default: --no-plain)

CREATE OPTIONS:
  --id <id>               Application identifier (default: net.example.MyApp)
  -d, --dir <directory>   Base folder for project creation
  -c, --configuration <c> Configuration debug/release (default: debug)
  -t, --template <id>     Template name/ID for new project (default: skipapp)
  -h, --template-host <host>
                          The host name for the template repository (default: https://github.com)
  -f, --template-file <zip>
                          A path to the template zip file to use
  --resource-path <resource-path>
                          Resource folder name (default: Resources)
  --chain/--no-chain      Create library dependencies between modules (default: --chain)
  --zero/--no-zero        Add SKIP_ZERO environment check to Package.swift (default: --zero)
  --git-repo/--no-git-repo
                          Create a local git repository for the app (default: --no-git-repo)
  --free                  Create package in free mode
  --show-tree/--no-show-tree
                          Display a file system tree summary of the new files (default: --no-show-tree)
  --module-tests/--no-module-tests
                          Whether to create test modules (default: --module-tests)
  --validate-package/--no-validate-package
                          Validate generated Package.swift files (default: --validate-package)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

BUILD OPTIONS:
  --build/--no-build      Run the project build (default: --build)
  --test/--no-test        Run the project tests (default: --no-test)
  --verify/--no-verify    Verify the project output (default: --verify)

OPTIONS:
  --appid <appid>         Embed the library as an app with the given bundle id
  --icon-color <RGB>      RGB hexadecimal color for icon background (default: 4994EC)
  --version <version>     Set the initial version to the given value
  --open-xcode            Open the resulting Xcode project
  --open-gradle           Open the resulting Gradle project
  -h, --help              Show help information.

```

## Troubleshooting

Skip's architecture relies on recent advances in the plugin system used by Xcode 15 and Swift Package Manager 5.9. When unexpected issues arise, often the best first step is to clean your Xcode build (`Product` → `Clean Build Folder`) and reset packages (`File` → `Packages` → `Reset Package Caches`). Restarting Xcode is sometimes warranted, and trashing the local `DerivedData/` folder might even be needed. 

Specific known error conditions are listed below. Search the [documentation](https://skip.tools/docs), [issues](https://source.skip.tools/skip/issues), and [discussions](http://community.skip.tools) for more information and to report problems.

- Xcode sometimes reports error messages like the following:

    ```shell
    Internal inconsistency error (didStartTask): targetID (174) not found in _activeTargets.
    Internal inconsistency error (didEndTask): '12' missing from _activeTasks.
    ```

    When these errors occur, the build appears to complete successfully although changes are not applied. Unfortunately, this is an Xcode bug. We have found the following workarounds:

    - Continue to retry the build. Eventually Xcode may complete successfully, although the errors often continue to become more frequent until you are forced to apply one of the other solutions below.
    - Building a different target and then re-building your app target may clear the error.
    - Restart Xcode.
    - Clean and rebuild.

    You can read more about this Xcode error on the [Swift.org forums](https://forums.swift.org/t/internal-inconsistency-error-didstarttask/61194).
- Skip may highlight the wrong line in build errors. When Skip surfaces the wrong line number, it is typically only one line off.
