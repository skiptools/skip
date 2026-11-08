# skipstone

This folder of the [skip](https://github.com/skiptools/skip) repository
hosts the Skip command-line tool "skip",
which is distributed as a binary plug-in through the releases at
[https://github.com/skiptools/skip/releases](https://github.com/skiptools/skip/releases)
as well as the Homebrew Cask via
[https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb](https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb).

The exact same binary is used by both the Xcode/SwiftPM `skipstone` build plugin
as well as the command-line tool installed via Homebrew's `brew install skip`

> [!NOTE]
> The `skipstone/` folder is a separate SwiftPM package from the `skip` plugin package at
> the root of the repository, and it is not built as part of it: the plugin normally downloads
> the pre-built `skip` binary from the releases, and only builds it from these sources when
> `SKIPLOCAL` is set (see [Local Skip Development](#local-skip-development)).
> The two packages share the `SkipDrive` sources through the `Sources/SkipDriveExternal`
> symbolic link, which points to `../../Sources/SkipDrive`.
> Note the naming inversion: this `skipstone/` package vends the `skip` tool, whereas the
> `skip` package at the root vends the `skipstone` plugin.

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
% brew tap skiptools/skip

==> Tapping skiptools/skip
Cloning into '/opt/homebrew/Library/Taps/skiptools/homebrew-skip'...
Tapped 1 cask (15 files, 417KB).

% brew install skip

==> Downloading https://source.skip.dev/skip/releases/download/1.0.0/skip.zip
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

Welcome to Skip 1.7.0!

Run "skip checkup" to perform a full system evaluation.
Run "skip create" to start a new project.

Visit https://skip.dev for documentation, samples, and FAQs.

Happy Skipping!

🍺  skip was successfully installed!
```

This will download and install the `skip` tool itself, as well as the `gradle` and Android SDK dependencies that are necessary for building and testing the Kotlin/Android side of your apps.

> [!NOTE]
> The `skip` tool installed via Homebrew is the exact same binary that is used by the Skip Xcode plugin, but they are installed in separate locations and updated through different mechanisms (the Homebrew [Cask](https://source.skip.dev/homebrew-skip/blob/main/Casks/skip.rb) for the CLI and the [skip/Package.swift](https://source.skip.dev/skip/blob/main/Package.swift) for the SwiftPM plugin).

> [!CAUTION]
> Linux and Windows support is preliminary and currently doesn't support many features, but it can be used for creating, building, testing, and exporting framework projects as well as running the `skip android` frontend for the Swift SDK for Android. For creating and building full app projects, macOS is required.

## Skip Commands

- `skip upgrade`: Upgrade to the latest Skip version
- `skip checkup`: Run tests to ensure Skip is in working order
- `skip create`: Create a new Skip project interactively
- `skip init`: Initialize a new Skip project
- `skip doctor`: Evaluate and diagnose Skip development environment
- `skip verify`: Verify Skip project
- `skip export`: Export the Gradle project and built artifacts
- `skip test`: Run parity tests and generate reports
- `skip icon`: Create and manage app icons
- `skip devices`: List connected devices and emulators/simulators
- `skip android`: Perform a native Android package command
- `skip android build`: Build the native project for Android
- `skip android test`: Test the native project on an Android device or emulator
- `skip android emulator create`: Install and create an Android emulator image
- `skip android emulator list`: List installed Android emulators
- `skip android emulator launch`: Launch an Android emulator
- `skip android sdk list`: List the installed Swift Android SDKs

## Native Package Mirroring

Native and bridged targets mirror the nearest ancestor containing `Package.swift`.
Conventional `Sources/<Target>` and `Tests/<TargetTests>` layouts retain the same
package root. Custom `path:` layouts now use their owning manifest instead of the
directory two levels above the target: this includes targets at the package root,
one directory below it, or deeper than the conventional two directories.

When a nested directory contains its own manifest, targets below it mirror that
nested package rather than the outer package. A target with no ancestor manifest
fails with a diagnostic. This discovery change does not change source enumeration
or the native test harness.

## Local Skip Development

Run `./scripts/skip` to build and run the Skip CLI tool from source. (It runs `swift run SkipRunner`, passing in a `$SKIP_COMMAND_OVERRIDE` environment variable.)

To build the `skip` plugin package at the root of the repository against the tool compiled
from these sources (rather than the released binary), set the `SKIPLOCAL` environment variable
when building or testing the root package, e.g. `SKIPLOCAL= swift test` from the repository root
(an empty value uses this `skipstone/` folder; a path uses that checkout instead).
This is what the `skip ci` workflow does.

In order to iterate on local changes to the `skipstone` binary that the Skip plugin uses from Xcode,
create an Xcode workspace that includes a local checkout of 
[`skip.git`](https://github.com/skiptools/skip.git)
(or a fork of it),
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
that it is a local debug build will be that there is an asterisk ("*") after the
Skip version number at the beginning of the skipstone plugin output, like so:

```console
Showing All Messages
Skip 1.7.0*: skipstone plugin to: /Users/marc/Library/Developer/Xcode/DerivedData/Skip-Everything-aqywrhrzhkbvfseiqgxuufbdwdft/Build/Intermediates.noindex/BuildToolPluginIntermediates/skip-lib.output/SkipLib/skipstone/SkipLib/src/main at 11:23:18
```

> [!CAUTION]
> If Xcode ever crashes (heaven forfend) and automatically re-starts, it will _not_ restart from the `skipstone` folder, which means that suddenly you will no longer be building against your local `skipstone` changes. This can be very confusing.
>
> Similarly, launching Xcode from the dock and using `Open Recent…` to open the project also will not happen from the `skipstone` directory.
>
> When in doubt, always just quit Xcode manually and re-launch your workspace from the `skipstone` folder from the Terminal again, and then verify that the local build of `skipstone` is being used with the logging indicators above.

## Releasing Skip

Releases are made by the
[`skip release`](../.github/workflows/release.yml)
GitHub Actions workflow, which runs the
[`scripts/release_skip.sh`](scripts/release_skip.sh)
script. Every push and the nightly schedule run the script as a dry run, which builds the
release artifacts and shows the changes a release would make without committing anything.
To make an actual release, dispatch the workflow manually from the Actions tab with the
"dry run" option unchecked, choosing which semantic version component to bump (patch by default).

The release workflow runs against the repository it is dispatched in, so a fork can rehearse
the whole process against its own releases. Updating the Homebrew cask in
[homebrew-skip](https://github.com/skiptools/homebrew-skip) requires a `RELEASE_TOKEN`
repository secret with write access to that repository; without it the cask update is skipped.

> [!NOTE]
> You must have write and release permissions for the repository in order to be able to create a release.

The script can also be run locally from a checkout of this repository. It builds the tool for both macOS and cross-compiles it for Linux, so you will need the [`swiftly`](https://www.swift.org/install/macos/swiftly/) tool installed as well as the [static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html). If a checkout of `homebrew-skip.git` exists in a peer folder of the repository, its cask is updated as well.

> [!TIP]
> To do a dry run of a release without trying to push or tag any changes, run `DRY_RUN=1 ./skipstone/scripts/release_skip.sh` from the repository root.

The release script will do the following:

1. Bump the `skipVersion` in both [`Sources/SkipSyntax/Version.swift`](Sources/SkipSyntax/Version.swift) and the plugin's [`Sources/SkipDrive/Version.swift`](../Sources/SkipDrive/Version.swift). By default this will bump the patch version, but running `SEMVER_BUMP='minor' ./skipstone/scripts/release_skip.sh` will instead bump the minor version.
1. Check that the `skip ci` and `skipstone CI` workflows have passed for the commit being released (override with `SKIP_RELEASE_IGNORE_CI=1`).
1. Build the universal macOS artifactbundle `skip-macos.zip` with [`scripts/build_macos_plugin.sh`](scripts/build_macos_plugin.sh)
1. Build the static Linux (MUSL) artifactbundle `skip-linux.zip` with [`scripts/build_linux_plugin.sh`](scripts/build_linux_plugin.sh)
1. Update the bundle URLs and checksums in the Skip plugin's [`Package.swift`](../Package.swift)
1. Commit, tag, and push the repository, and create the [GitHub release](https://github.com/skiptools/skip/releases) with the two artifactbundles attached
1. Update the version, binary URLs, and checksums for the Homebrew Cask's [`skip.rb`](https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb), and commit, tag, and push `homebrew-skip.git`
1. When run locally, upgrade Skip on the local machine with `brew upgrade skiptools/skip/skip` and run `skip welcome`

As a post-release step, it is a good idea to make sure that `skip checkup --native` works on the local machine.

## Contributing

Contributions are welcome! Fork the repository and make local changes,
and ensure that all the test cases pass (either via Xcode or with `swift test` from the Terminal).

The Contributor License Agreement (CLA) can be signed
by adding your GitHub username in the
[`clabot-config`](https://github.com/skiptools/clabot-config/edit/main/.clabot)
before submitting pull requests.

It is wise to discuss any major intended changes on the
[discussions](https://github.com/orgs/skiptools/discussions/)
board before embarking on any big projects.
