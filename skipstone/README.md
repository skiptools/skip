# skipstone

This repository hosts the Skip command-line tool "skip",
which is distributed as a binary plug-in through the public repo at
[https://github.com/skiptools/skip/releases](https://github.com/skiptools/skip/releases)
as well as the Homebrew Cask via
[https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb](https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb).

The exact same binary is used by both the Xcode/SwiftPM `skipstone` build plugin
as well as the command-line tool installed via Homebrew's `brew install skiptools/skip/skip`

> [!CAUTION]
> This repository, https://github.com/skiptools/skipstone.git, vends the `skip` tool,
> whereas the https://github.com/skiptools/skip.git repository vends the `skipstone` plugin.
> The names are the reverse of what you might expect.

The `skip` tool itself is a stand-alone cross-platform command-line executable that
contains a plethora of commands that support the
creation of Skip projects, the transpilation and bridge-building
that facilitate bi-directional communication between Swift and Kotlin on Android,
transformers from SwiftPM projects into Gradle projects,
resource converters for .xcassets and .xcstrings bundles to turn them
into Android assets, a front-end for the Swift SDK for Android, Gradle,
and the Android emulator, and much more.

## Installing

The `skip` CLI is installed using [Homebrew](https://brew.sh). Skip is distributed as a binary Homebrew "Cask" for macOS, Linux, and Windows (with [WSL 2](https://learn.microsoft.com/en-us/windows/wsl/about)). For complete details, see the [Getting Started Guide](/docs/gettingstarted/).

Once Homebrew is set up, Skip can be installed (and updated) by running the Terminal command:

```console title="Installing skip with Homebrew"
% brew install skiptools/skip/skip

==> Tapping skiptools/skip
Cloning into '/opt/homebrew/Library/Taps/skiptools/homebrew-skip'...
Tapped 1 cask (15 files, 417KB).
==> Downloading https://source.skip.tools/skip/releases/download/1.0.0/skip.zip
==> Installing dependencies: android-platform-tools
==> Downloading https://dl.google.com/android/repository/platform-tools_r34.0.5-darwin.zip
==> Installing Cask android-platform-tools
==> Linking Binary 'adb' to '/opt/homebrew/bin/adb'
🍺  android-platform-tools was successfully installed!
==> Installing Cask skip
==> Linking Binary 'skip' to '/opt/homebrew/bin/skip'


  ▄▄▄▄▄▄▄  ▄▄▄  ▄▄▄ ▄▄  ▄▄▄▄▄▄▄ 
 █       ██   █ █ ██  ██       █
 █  ▄▄▄▄▄██   █▄█ ██  ██    ▄  █
 █ █▄▄▄▄▄██      ▄██  ██   █▄█ █
 █▄▄▄▄▄  ██     █▄██  ██    ▄▄▄█
  ▄▄▄▄▄█ ██    ▄  ██  ██   █    
 █▄▄▄▄▄▄▄██▄▄▄█ █▄██▄▄██▄▄▄█    

Welcome to Skip 1.6.36!

Run "skip checkup" to perform a full system evaluation.
Run "skip create" to start a new project.

Visit https://skip.dev for documentation, samples, and FAQs.

Happy Skipping!

🍺  skip was successfully installed!
```

This will download and install the `skip` tool itself, as well as the `gradle` and Android SDK dependencies that are necessary for building and testing the Kotlin/Android side of your apps.

> [!NOTE]
> The `skip` tool installed via Homebrew is the exact same binary that is used by the Skip Xcode plugin, but they are installed in separate locations and updated through different mechanisms (the Homebrew [Cask](https://source.skip.tools/homebrew-skip/blob/main/Casks/skip.rb) for the CLI and the [skip/Package.swift](https://source.skip.tools/skip/blob/main/Package.swift) for the SwiftPM plugin).

> [!CAUTION]
> Linux and Windows support is preliminary and currently doesn't support many features, but it can be used for creating, building, testing, and exporting framework projects as well as running the `skip android` frontend for the Swift SDK for Android. For creating and building full app projects, macOS is required.

---

## Skip Commands {#intro}

```console title="skip command output"
OVERVIEW: skip 1.6.36

USAGE: skip <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  version                 Print the skip version
  doctor                  Evaluate and diagnose Skip development environment
  checkup                 Run tests to ensure Skip is in working order
  upgrade                 Upgrade to the latest Skip version
  create                  Create a new Skip project interactively
  init                    Initialize a new Skip project
  verify                  Verify Skip project
  icon                    Create and manage app icons
  android                 Perform a native Android package command
  export                  Export the Gradle project and built artifacts
  devices                 List connected devices and emulators/simulators
  test                    Run parity tests and generate reports

  See 'skip help <subcommand>' for detailed help.
```

### skip upgrade: Upgrade to the latest Skip version {#upgrade}

```console title="skip upgrade command output"
OVERVIEW: Upgrade to the latest Skip version

USAGE: skip upgrade <options>

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  -h, --help              Show help information.

```

### skip checkup: Run tests to ensure Skip is in working order {#checkup}

```console title="skip checkup command output"
OVERVIEW: Run tests to ensure Skip is in working order

This command performs a full system checkup to ensure that Skip can create and
build a sample project. It runs all the checks performed by skip doctor, and
also creates and builds a conventional Skip app project.

USAGE: # Perform a basic system checkup
       skip checkup

       # Perform a system checkup for native app support
       skip checkup --native

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  -c, --configuration <c> Configuration debug/release (default: debug)
  --double-check          Check twice that sample build outputs produce
                          identical artifacts
  --native                Generate native app when running checkup
  --native-app            Generate native app when running checkup
  --native-model          Generate native module when running checkup
  --fail-fast/--no-fail-fast
                          Fail immediately when an error occurs (default:
                          --fail-fast)
  --project-name <name>   Name of checkup project (default: hello-skip)
  --module-name <module-name>
                          Name of checkup project module (default: HelloSkip)
  -h, --help              Show help information.

```

### skip create: Create a new Skip project interactively {#create}

```console title="skip create command output"
OVERVIEW: Create a new Skip project interactively

Create a new project by following a series of interactive prompts.

USAGE: skip create <options>

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

TOOLCHAIN OPTIONS:
  --swift-version <v>     Swift version to use
  --sdk <path>            Swift Android SDK path
  --ndk <path>            Android NDK path
  --toolchain <path>      Swift toolchain path
  --package-path <path>   Path to the package to run
  --scratch-path <.build> Custom scratch directory path
  -Xswiftc <Xswiftc>      Pass flag through to all Swift compiler invocations
  -Xcc <Xcc>              Pass flag through to all C compiler invocations
  -Xlinker <Xlinker>      Pass flag through to all linker invocations
  -Xcxx <Xcxx>            Pass flag through to all C++ compiler invocations
  -c, --configuration <debug>
                          Build with configuration
  --arch <arch>           Destination architectures (values: automatic,
                          current, default, all, aarch64, armv7, x86_64)
  --android-api-level <level>
                          Android API level (default: 28)
  --swift-sdk-home <path> Root path for Swift SDK
  --bridge/--no-bridge    Enable SKIP_BRIDGE bridging to Kotlin (default:
                          --bridge)
  --aggregate/--no-aggregate
                          Enable bundling all libraries into a single shared
                          object (default: --no-aggregate)
  --prune/--no-prune      Prune non-dependent libraries from build output
                          (default: --prune)

CREATE OPTIONS:
  -d, --dir <directory>   Base folder for project creation
  -c, --configuration <c> Configuration debug/release (default: debug)
  --resource-path <resource-path>
                          Resource folder name (default: Resources)
  --swift-version <swift-version>
                          Swift version for project (default: 6.1)
  --ios-min-version <ios-min-version>
                          Minimum iOS version to target (default: 17.0)
  --macos-min-version <macos-min-version>
                          Minimum macOS version to target
  --chain/--no-chain      Create library dependencies between modules (default:
                          --chain)
  --zero/--no-zero        Add SKIP_ZERO environment check to Package.swift
                          (default: --no-zero)
  --git-repo/--no-git-repo
                          Create a local git repository for the app (default:
                          --no-git-repo)
  --free                  Create package with free software license
  --show-tree/--no-show-tree
                          Display a file system tree summary of the new files
                          (default: --no-show-tree)
  --kotlincompat/--no-kotlincompat
                          Whether native model should use kotlincompat
                          (default: --no-kotlincompat)
  --bridged/--no-bridged  Whether transpiled model should br bridged (default:
                          --no-bridged)
  --module-tests/--no-module-tests
                          Whether to create test modules
  --fastlane/--no-fastlane
                          Whether to create fastlane metadata (default:
                          --fastlane)
  --github/--no-github    Whether to create github metadata (default:
                          --no-github)
  --validate-package/--no-validate-package
                          Validate generated Package.swift files (default:
                          --validate-package)

OPTIONS:
  -h, --help              Show help information.

```

### skip init: Initialize a new Skip project {#init}

```console title="skip init command output"
OVERVIEW: Initialize a new Skip project

This command will create a conventional Skip app or library project.

USAGE: # Create a new native Skip Fuse app project
       skip init --native-app --appid=some.app.id app-project AppName

       # Create a new transpiled Skip Lite app project
       skip init --transpiled-app --appid=some.app.id app-project AppName

       # Create a new native library project
       skip init --native-model lib-project ModuleName

       # Create a new transpiled library project
       skip init --transpiled-model lib-project ModuleName

       # Create a new app project with multiple modules
       skip init --native-app --appid=some.app.id app-project AppName ModuleName

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
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

CREATE OPTIONS:
  -d, --dir <directory>   Base folder for project creation
  -c, --configuration <c> Configuration debug/release (default: debug)
  --resource-path <resource-path>
                          Resource folder name (default: Resources)
  --swift-version <swift-version>
                          Swift version for project (default: 6.1)
  --ios-min-version <ios-min-version>
                          Minimum iOS version to target (default: 17.0)
  --macos-min-version <macos-min-version>
                          Minimum macOS version to target
  --chain/--no-chain      Create library dependencies between modules (default:
                          --chain)
  --zero/--no-zero        Add SKIP_ZERO environment check to Package.swift
                          (default: --no-zero)
  --git-repo/--no-git-repo
                          Create a local git repository for the app (default:
                          --no-git-repo)
  --free                  Create package with free software license
  --show-tree/--no-show-tree
                          Display a file system tree summary of the new files
                          (default: --no-show-tree)
  --kotlincompat/--no-kotlincompat
                          Whether native model should use kotlincompat
                          (default: --no-kotlincompat)
  --bridged/--no-bridged  Whether transpiled model should br bridged (default:
                          --no-bridged)
  --module-tests/--no-module-tests
                          Whether to create test modules
  --fastlane/--no-fastlane
                          Whether to create fastlane metadata (default:
                          --fastlane)
  --github/--no-github    Whether to create github metadata (default:
                          --no-github)
  --validate-package/--no-validate-package
                          Validate generated Package.swift files (default:
                          --validate-package)

PROJECT OPTIONS:
  --native-app/--transpiled-app/--native-model/--transpiled-model

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
  --verify/--no-verify    Verify the project output (default: --no-verify)

OPTIONS:
  --appid <bundleID>      Embed the library as an app with the given bundle id
  --no-icon               Disable icon generation
  --icon <icon>           Path to icon input file (SVG, PDF, PNG)
  --icon-background <hex> RGB hexadecimal color for icon background
  --icon-foreground <hex> RGB hexadecimal color for icon foreground
  --icon-shadow <decimal> The amount of shadow to draw around the target
  --icon-inset <decimal>  The amount of inset to place on the image
  --version <version>     Set the initial version to the given value
  --apk/--no-apk          Build the Android .apk file (default: --no-apk)
  --ipa/--no-ipa          Build the iOS .ipa file (default: --no-ipa)
  --open-xcode            Open the resulting Xcode project
  --open-gradle           Open the resulting Gradle project
  -h, --help              Show help information.

```

### skip doctor: Evaluate and diagnose Skip development environment {#doctor}

```console title="skip doctor command output"
OVERVIEW: Evaluate and diagnose Skip development environment

This command will check for system configuration and prerequisites. It is a
subset of the skip checkup command.

USAGE: skip doctor <options>

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  --native/--no-native    Check for native SDK (default: --no-native)
  --fail-fast/--no-fail-fast
                          Fail immediately when an error occurs (default:
                          --no-fail-fast)
  -h, --help              Show help information.

```

### skip verify: Verify Skip project {#verify}

```console title="skip verify command output"
OVERVIEW: Verify Skip project

This command is run on a Skip project to ensure that the structure and contents
are valid.

USAGE: skip verify <options>

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  --project <dir>         Project folder (default: .)
  --free/--no-free        Validate free project
  --fastlane/--no-fastlane
                          Validate fastlane config
  --fail-fast/--no-fail-fast
                          Fail immediately when an error occurs (default:
                          --no-fail-fast)
  --fix/--no-fix          Attempt to automatically fix issues (default:
                          --no-fix)
  -h, --help              Show help information.

```

### skip export: Export the Gradle project and built artifacts {#export}

```console title="skip export command output"
OVERVIEW: Export the Gradle project and built artifacts

Build and export the Skip modules defined in the Package.swift, with libraries
exported as .aar files and the app exported as an .apk and .adb file suitable
for distribution.

USAGE: # export just the debug version of the archives
       skip export --debug

       # export just the "ModuleName" module
       skip export --module ModuleName

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  -d, --dir <directory>   Export output folder
  --package <package-name>
                          App package name
  --module <ModuleName>   Modules to export
  --project <dir>         Project folder (default: .)
  --summary-file <file>   Output summary path
  --build/--no-build      Build the Swift project before exporting (default:
                          --build)
  --show-tree/--no-show-tree
                          Display a file system tree summary (default:
                          --no-show-tree)
  --release               Perform release build
  --debug                 Perform debug build
  --export-project/--no-export-project
                          Export project sources (default: --export-project)
  --ios/--no-ios          Export iOS .ipa (default: --ios)
  --android/--no-android  Export Android .apk (default: --android)
  --nested/--no-nested    Output folders to variant sub-folders (default:
                          --no-nested)
  --sdk-path <sdk dir>    SDK path for export build
  --scheme-name <scheme>  Project scheme name to export
  --arch <arch>           Destination architectures for native libraries
                          (values: automatic, current, default, all, aarch64,
                          armv7, x86_64)
  -h, --help              Show help information.

```

### skip test: Run parity tests and generate reports {#test}

```console title="skip test command output"
OVERVIEW: Run parity tests and generate reports

USAGE: skip test <options>

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  --test/--no-test        Run the project tests (default: --test)
  --filter <Test.testFun> Test filter(s) to run
  --project <dir>         Project folder (default: .)
  --xunit <xunit.xml>     Path to xunit test report
  --junit <folder>        Path to junit test report
  --max-column-length <n> Maximum table column length (default: 25)
  -c, --configuration <c> Configuration debug/release (default: debug)
  --summary-file <path>   Output summary table
  -h, --help              Show help information.

```

### skip icon: Create and manage app icons {#icon}

```console title="skip icon command output"
OVERVIEW: Create and manage app icons

This command will create and update icons in the Darwin and Android folders of
a Skip project.

skip icon should be run in the root folder of a conventional Skip app project
that contains Darwin and Android folders.

USAGE: # Resize the given PNG icon for each of the required icon sizes
       skip icon app_icon.png

       # Resize separate icons for each of Android and iOS
       skip icon --android app_icon_android.png
       skip icon --darwin app_icon_darwin.png

       # Generate a random icon set and open them in Preview.app
       skip icon --open-preview --random-icon --random-background

       # Generate new icons with a named color background
       skip icon --open-preview --background skyblue

       # Create new icons with a background gradient
       skip icon --open-preview --background #3E8E41-#2F4F4F

       # Create new icons with a background gradient overlaid with an SVG image
       skip icon --open-preview --background #5C6BC0-#3B3F54 symbol.svg

       # Create new icons with custom image inset and shadow radius
       skip icon --background #F7DC6F-#F2C464 --inset 0.4 --shadow 0.02 symbol.svg

ARGUMENTS:
  <icon-sources>          Path or URL to icon source SVG, PNG, or PDF files

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

OPTIONS:
  -d, --dir <directory>   Root folder for icon generation
  --open-preview          Open the generated icons in Preview
  --android/--no-android  Generate an Android icon set
  --android-path <path>   Path the Android resources root folder (default:
                          Android/app/src/main/res)
  --darwin/--no-darwin    Generate an Android icon set
  --darwin-path <path>    Path the Darwin icon assets folder (default:
                          Darwin/Assets.xcassets/AppIcon.appiconset)
  --foreground <color>    Name or RGB hex color/gradient for icon color
                          (default: white)
  --background <color>    Name or RGB hex color/gradient for icon background
  --inset <amount>        The percentage amount of inset for the shape
                          (default: 0.1)
  --shadow <amount>       The percentage amount of shadow to dear around the
                          path (default: 0.01)
  --random-icon           Create a random icon shape
  --random-background     Create a random icon color
  -h, --help              Show help information.

```

### skip devices: List connected devices and emulators/simulators {#devices}

```console title="skip devices command output"
OVERVIEW: List connected devices and emulators/simulators

This command will list all the connected Android emulators and devices and iOS
simulators and devices.

USAGE: skip devices <options>

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

OPTIONS:
  -h, --help              Show help information.

```

### skip android: Perform a native Android package command {#android}

```console title="skip android command output"
OVERVIEW: Perform a native Android package command

USAGE: skip android <subcommand>

OPTIONS:
  -h, --help              Show help information.

SUBCOMMANDS:
  build                   Build the native project for Android
  run                     Run the executable target Android device or emulator
  test                    Test the native project on an Android device or
                          emulator
  sdk                     Manage installation of Swift Android SDK
  emulator                Manage Android emulators
  toolchain               Manage installation of Swift Android Host Toolchain

  See 'skip help android <subcommand>' for detailed help.
```

### skip android build: Build the native project for Android {#android-build}

```console title="skip android build command output"
OVERVIEW: Build the native project for Android

USAGE: skip android build [<options>] [<args> ...]

ARGUMENTS:
  <args>                  Command arguments

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

TOOLCHAIN OPTIONS:
  --swift-version <v>     Swift version to use
  --sdk <path>            Swift Android SDK path
  --ndk <path>            Android NDK path
  --toolchain <path>      Swift toolchain path
  --package-path <path>   Path to the package to run
  --scratch-path <.build> Custom scratch directory path
  -Xswiftc <Xswiftc>      Pass flag through to all Swift compiler invocations
  -Xcc <Xcc>              Pass flag through to all C compiler invocations
  -Xlinker <Xlinker>      Pass flag through to all linker invocations
  -Xcxx <Xcxx>            Pass flag through to all C++ compiler invocations
  -c, --configuration <debug>
                          Build with configuration
  --arch <arch>           Destination architectures (values: automatic,
                          current, default, all, aarch64, armv7, x86_64)
  --android-api-level <level>
                          Android API level (default: 28)
  --swift-sdk-home <path> Root path for Swift SDK
  --bridge/--no-bridge    Enable SKIP_BRIDGE bridging to Kotlin (default:
                          --bridge)
  --aggregate/--no-aggregate
                          Enable bundling all libraries into a single shared
                          object (default: --no-aggregate)
  --prune/--no-prune      Prune non-dependent libraries from build output
                          (default: --prune)

OPTIONS:
  -d, --dir <directory>   Archive output folder
  -h, --help              Show help information.

```

### skip android test: Test the native project on an Android device or emulator {#android-test}

```console title="skip android test command output"
OVERVIEW: Test the native project on an Android device or emulator

USAGE: skip android test [<options>] [<args> ...]

ARGUMENTS:
  <args>                  Command arguments

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

TOOLCHAIN OPTIONS:
  --swift-version <v>     Swift version to use
  --sdk <path>            Swift Android SDK path
  --ndk <path>            Android NDK path
  --toolchain <path>      Swift toolchain path
  --package-path <path>   Path to the package to run
  --scratch-path <.build> Custom scratch directory path
  -Xswiftc <Xswiftc>      Pass flag through to all Swift compiler invocations
  -Xcc <Xcc>              Pass flag through to all C compiler invocations
  -Xlinker <Xlinker>      Pass flag through to all linker invocations
  -Xcxx <Xcxx>            Pass flag through to all C++ compiler invocations
  -c, --configuration <debug>
                          Build with configuration
  --arch <arch>           Destination architectures (values: automatic,
                          current, default, all, aarch64, armv7, x86_64)
  --android-api-level <level>
                          Android API level (default: 28)
  --swift-sdk-home <path> Root path for Swift SDK
  --bridge/--no-bridge    Enable SKIP_BRIDGE bridging to Kotlin (default:
                          --bridge)
  --aggregate/--no-aggregate
                          Enable bundling all libraries into a single shared
                          object (default: --no-aggregate)
  --prune/--no-prune      Prune non-dependent libraries from build output
                          (default: --prune)

OPTIONS:
  --cleanup/--no-cleanup  Cleanup test folders after running (default:
                          --cleanup)
  --remote-folder <path>  Remote folder on emulator/device for build upload
  --testing-library <library>
                          Testing library name (default: all)
  --env <key=value>       Environment key/value pairs for remote execution
  --copy <file/folder>    Additional files or folders to copy to Android
  -h, --help              Show help information.

```

### skip android emulator create: Install and create an Android emulator image {#android-emulator-create}

```console title="skip android emulator create command output"
OVERVIEW: Install and create an Android emulator image

This command acts as a frontend to the Android SDK tools sdkmanager,
avdmanager, and emulator. Run with the --verbose argument to observe the exact
commands that it executes.

USAGE: # Creates the default Android emulator (API 34)
       skip android emulator create

       # Creates a custom Android emulator
       skip android emulator create --name 'pixel_7_api_36' --device-profile pixel_7 --android-api-level 36 --system-image google_apis_playstore_ps16k

       # Installs a specific emulator package
       android emulator install --package 'system-images;android-31;default;arm64-v8a'


OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

OPTIONS:
  --android-api-level <level>
                          Android API emulator level (default: 34)
  --device-profile <profile>
                          Android emulator device profile (default:
                          medium_phone)
  -n, --name <name>       Android emulator name
  --package <package>     The full package name of the emulator to install
  --system-image <image>  Android emulator APIs (default: google_apis)
  --arch <arch>           Android emulator architecture (default: arm64-v8a)
  -h, --help              Show help information.

```

### skip android emulator list: List installed Android emulators {#android-emulator-list}

```console title="skip android emulator list command output"
OVERVIEW: List installed Android emulators

USAGE: skip android emulator list <options>

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  -h, --help              Show help information.

```

### skip android emulator launch: Launch an Android emulator {#android-emulator-launch}

```console title="skip android emulator launch command output"
OVERVIEW: Launch an Android emulator

This command acts as a frontend to the Android SDK emulator command.
Install new emulators with: skip android emulator create
List installed emulators with: skip android emulator list
Run with the --verbose argument to observe the exact commands that it executes.

USAGE: # Launches the most recently created or used emulator
       skip android emulator launch

       # Launches an emulator with a certain name
       skip android emulator launch --name emulator-34-medium_phone


ARGUMENTS:
  <args>                  Emulator arguments

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OPTIONS:
  -n, --name <name>       Android emulator name
  --logcat <filter>       Logcat filter (see
                          https://developer.android.com/tools/logcat) (default:
                          *:D)
  --background/--no-background
                          Background the emulator process once it is launched
                          (default: --no-background)
  --headless/--no-headless
                          Run in headless mode (default: --no-headless)
  -h, --help              Show help information.

```

### skip android sdk list: List the installed Swift Android SDKs {#android-sdk-list}

```console title="skip android sdk list command output"
OVERVIEW: List the installed Swift Android SDKs

USAGE: skip android sdk list <options>

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

OPTIONS:
  --remote                List remote SDKs that can be installed
  --devel                 Include development SDKs in remote list
  -h, --help              Show help information.

```

### skip android sdk install: Install the native Swift Android SDK {#android-sdk-install}

```console title="skip android sdk install command output"
OVERVIEW: Install the native Swift Android SDK

USAGE: # Installs the default version of the Android SDK
       skip android sdk install

       # Installs the latest nightly for 6.3
       skip android sdk install --version nightly-6.3

OUTPUT OPTIONS:
  -o, --output <path>     Send output to the given file (stdout: -)
  -E, --message-errout    Emit messages to the output rather than stderr
  -v, --verbose           Whether to display verbose messages
  -q, --quiet             Quiet mode: suppress output
  -J, --json              Emit output as formatted JSON
  -j, --json-compact      Emit output as compact JSON
  -M, --message-plain     Show console messages as plain text rather than JSON
  --log-file <path>       Send log output to the file
  -A, --json-array        Wrap and delimit JSON output as an array
  --plain/--no-plain      Show no colors or progress animations (default:
                          --no-plain)

TOOL OPTIONS:
  --xcodebuild <path>     Xcode command path
  --swift <path>          Swift command path
  --gradle <path>         Gradle command path
  --adb <path>            ADB command path
  --emulator <path>       Android emulator path
  --android-home <path>   Path to the Android SDK (ANDROID_HOME)

TOOLCHAIN OPTIONS:
  --swift-version <v>     Swift version to use
  --sdk <path>            Swift Android SDK path
  --ndk <path>            Android NDK path
  --toolchain <path>      Swift toolchain path
  --package-path <path>   Path to the package to run
  --scratch-path <.build> Custom scratch directory path
  -Xswiftc <Xswiftc>      Pass flag through to all Swift compiler invocations
  -Xcc <Xcc>              Pass flag through to all C compiler invocations
  -Xlinker <Xlinker>      Pass flag through to all linker invocations
  -Xcxx <Xcxx>            Pass flag through to all C++ compiler invocations
  -c, --configuration <debug>
                          Build with configuration
  --arch <arch>           Destination architectures (values: automatic,
                          current, default, all, aarch64, armv7, x86_64)
  --android-api-level <level>
                          Android API level (default: 28)
  --swift-sdk-home <path> Root path for Swift SDK
  --bridge/--no-bridge    Enable SKIP_BRIDGE bridging to Kotlin (default:
                          --bridge)
  --aggregate/--no-aggregate
                          Enable bundling all libraries into a single shared
                          object (default: --no-aggregate)
  --prune/--no-prune      Prune non-dependent libraries from build output
                          (default: --prune)

OPTIONS:
  --version <version>     Version of the Swift Android SDK to install (default:
                          6.2)
  --ndk-version <ndk>     Version of the Android NDK to link to the toolchain
                          (default: r27d)
  --reinstall             Reinstall the Android SDK
  --verify/--no-verify    Verify Android SDK installation (default: --verify)
  -h, --help              Show help information.

```

## Local Skip Development

In order to iterate on local changes to the `skipstone` binary that the Skip plugin uses,
create an Xcode workspace that includes a local checkout of 
[`skipstone.git`](https://github.com/skiptools/skipstone.git)
and
[`skip.git`](https://github.com/skiptools/skip.git)
(or forks of those repositories),
along with any Skip apps or frameworks where you want to test the changes.

The key is that the _current working directory for Xcode must be the `skipstone` folder_.
This is the magic property that tells the Skip plugin to use the locally-built `skip` binary
rather than the remote binary that is referenced by the plugins specification in `Package.skip`.

In order to open Xcode from the `skipstone` folder, it **must** be done from the Terminal,
like so:

```console
cd skipstone/
open /path/to/my/project.xcworkspace
```

If you are successfully using the local Skip build for your plugin, this will be
indicated in the Xcode Build log in the Report Navigator tab. E.g., when launching a Skip app,
expanding the `Run skip gradle` messages will reference the _local_ build of `skip`,
like so:

```console
Showing All Messages
running gradle build with: /Users/marc/Library/Developer/Xcode/DerivedData/Skip-Everything-aqywrhrzhkbvfseiqgxuufbdwdft/Build/Products/Debug/skip gradle -p /opt/src/github/skiptools/skipapp-godot-demo/Darwin/../Android launchDebug
```

For framework projects (e.g., when building or running tests), the indication that it is
using the local build will come from the plugin log message for the target. The indication
that it is a local debug build will be that there is an asterisk ("*") agfter the
Skip version number at the beginning of the skipstone plugin output, like so:

```console
Showing All Messages
Skip 1.6.36*: skipstone plugin to: /Users/marc/Library/Developer/Xcode/DerivedData/Skip-Everything-aqywrhrzhkbvfseiqgxuufbdwdft/Build/Intermediates.noindex/BuildToolPluginIntermediates/skip-lib.output/SkipLib/skipstone/SkipLib/src/main at 11:23:18
```

> [!CAUTION]
> If Xcode ever crashes (heaven forfend) and automatically re-starts, it will _not_ restart from the `skipstone` folder, which means that suddenly you will no longer be building against your local `skipstone` changes. This can be very confusing.
>
> Similarly, launching Xcode from the dock and using `Open Recent…` to open the project also will not happen from the `skipstone` directory.
>
> When in doubt, always just quit Xcode manually and re-launch your workspace from the `skipstone` folder from the Terminal again, and then verify that the local build of `skipstone` is being used with the logging indicators above.

## Releasing Skip

Creating a release of skipstone is done with the
[`scripts/release_skip.sh`](scripts/release_skip.sh)
script, which requires that each three repositories are checkout in peer folders:

- https://github.com/skiptools/skipstone.git
- https://github.com/skiptools/skip.git
- https://github.com/skiptools/homebrew-skip.git

> [!NOTE]
> You must have write and release permissions for each of these repositories in order to be able to create a release.

> [!TIP]
> To do a dry run of a release without trying to push or tag any changes, run `DRY_RUN=1 ./scripts/release_skip.sh`

The release script will do the following:

1. Bump the `skipVersion` in [`Sources/SkipSyntax/Version.swift`](Sources/SkipSyntax/Version.swift). By default this will bump the patch version, but running `SEMVER_BUMP='minor' ./scripts/release_skip.sh` will instead bump the minor version.
1. Build the universal macOS artifactbundle `skip-macos.zip` with [`scripts/build_macos_plugin.sh`](scripts/build_macos_plugin.sh).
1. Build the static Linux (MUSL) artifactbundle `skip-linux.zip` with [`scripts/build_linux_plugin.sh`](scripts/build_linux_plugin.sh).
1. Update the bundle URLs and checksums in the Skip plugin's [`Package.swift`](https://github.com/skiptools/skip/blob/main/Package.swift).
1. Update the binary URLs and checksums for the Homebrew Cask's [`skip.rb`](https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb).
1. Commit, tag, and push each of `skipstone.git`, `skip.git`, and `homebrew-skip.git`
1. Create GitHub releases for each of [`skipstone.git`](https://github.com/skiptools/skipstone/releases) and [`skip.git`](https://github.com/skiptools/skip/releases)
1. Try to upgrade Skip on the local machine with `brew upgrade skiptools/skip/skip`
1. Run `skip welcome`


## Contributing

Contributions are welcome! Fork the repository and make local changes,
and ensure that all the test cases pass (either via Xcode or with `swift test` from the Terminal).

We do require signing a Contributor License Agreement (CLA)
by adding your GitHub username in the
[`clabot-config`](https://github.com/skiptools/clabot-config/edit/main/.clabot)
before submitting pull requests.

It is wise to discuss any major intended changes on the
[discussions](https://github.com/orgs/skiptools/discussions/)
before embarking on any major projects.

## License

Distributed under the GNU Affero General Public License v3.0 License.
See [`LICENSE.txt`](LICENSE.txt) for more information.

