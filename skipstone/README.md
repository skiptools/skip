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

A release of Skip publishes a new version of both the `skip` command-line tool and the `skip`
SwiftPM plugin package. Releases are made entirely by the
[`skip release`](../.github/workflows/release.yml) GitHub Actions workflow: a maintainer only
picks the version number and starts the workflow, either by pushing a version tag from the command
line or by running the workflow from the GitHub web UI. The workflow then does the rest:

1. Checks that the commit is on `main`, that no release of that version exists yet, and that the
   `skip ci` and `skipstone CI` workflows have passed for exactly that commit.
1. Sets `skipVersion` to the release version in both
   [`Sources/SkipSyntax/Version.swift`](Sources/SkipSyntax/Version.swift) (the tool) and
   [`Sources/SkipDrive/Version.swift`](../Sources/SkipDrive/Version.swift) (the plugin), and fails
   unless each file then declares exactly `public let skipVersion = "<version>"`.
1. Builds the universal macOS artifactbundle `skip-macos.zip` with
   [`scripts/build_macos_plugin.sh`](scripts/build_macos_plugin.sh) and the static Linux (musl)
   artifactbundle `skip-linux.zip` with [`scripts/build_linux_plugin.sh`](scripts/build_linux_plugin.sh).
1. Points the binary targets in the plugin's [`Package.swift`](../Package.swift) at the new
   artifacts and their checksums.
1. Commits these changes as "Release X.Y.Z" on `main`, moves the version tag onto that commit, and
   creates the [GitHub release](https://github.com/skiptools/skip/releases) with both artifactbundles
   attached.
1. Updates the version and checksums of the Homebrew cask
   [`Casks/skip.rb`](https://github.com/skiptools/homebrew-skip/blob/main/Casks/skip.rb), and
   commits, tags, and pushes it to `homebrew-skip`.

The steps are implemented by [`scripts/release_skip.sh`](scripts/release_skip.sh), which the
workflow runs. The script refuses to make a real release anywhere but GitHub Actions (see
[Dry runs](#dry-runs) for checking a release build locally).

### Required permissions

- **To cut a release:** the *Write*, *Maintain*, or *Admin* role on
  [skiptools/skip](https://github.com/skiptools/skip). Write access is what GitHub requires both
  to push a tag and to run a workflow from the Actions tab. Nothing else is needed on the
  maintainer's side: no signing keys, local toolchains, or access to `homebrew-skip`, because the
  workflow pushes everything with the `RELEASE_TOKEN` secret. Since there are no tag protection
  rules, anyone with write access can make a release.
- **To manage the `RELEASE_TOKEN` secret:** the *Admin* role on skiptools/skip (repository
  *Settings → Secrets and variables → Actions*). The secret is a fine-grained personal access token
  whose resource owner is `skiptools`, limited to the `skip` and `homebrew-skip` repositories, with
  the **Contents: Read and write** and **Actions: Read** permissions; the account that owns it
  must itself have write access to both repositories. When the token expires, the release
  workflow fails at its first checkout step (so the nightly dry run starts failing too), so rotate
  it before then. Without the secret, the workflow falls back to
  the workflow's own token, which can release `skip` but cannot push to `homebrew-skip`, so the
  cask update is skipped.
- **To update the Homebrew formula** (see [After the release](#after-the-release)): any GitHub
  account can open the pull request from a fork of
  [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core); it is merged by Homebrew's
  maintainers.

### Before you release

**Do not bump the version by hand.** There are no version changes to commit before a release: the
workflow sets `skipVersion` in both `Version.swift` files as part of the release commit, and checks
that they match the release version exactly. Bumping them ahead of time would in fact break the
release, because release builds of the tool make new projects depend on the `skip` package
`from: "<skipVersion>"` (see [`SkipProject.swift`](Sources/SkipBuild/SkipProject.swift)), so the `skipstone CI` tests would fail to resolve
a version that has not been released yet, and the release would then refuse to run for the
failing commit.

What you do need to check:

1. **Choose the version.** Releases use plain semantic versions with no `v` prefix (e.g. `1.9.21`).
   Pick the next version after the [latest release](https://github.com/skiptools/skip/releases)
   (`gh release list -R skiptools/skip -L 1`).
1. **Make sure CI is green for the commit you are releasing.** The `skip ci` and `skipstone CI`
   workflows must have succeeded for that exact commit on `main` (the most recent completed run of
   each is what counts, including the scheduled runs). The `skip checks` workflow tests the
   previously released Homebrew build, so it does not gate a release.

### Releasing from the command line

With the [GitHub CLI](https://cli.github.com) installed and authenticated, from a checkout of skip:

```console
git switch main
git pull

# confirm that both CI workflows passed for this exact commit
gh run list --workflow ci.yml --commit "$(git rev-parse HEAD)" --status completed --limit 1
gh run list --workflow skipstone-ci.yml --commit "$(git rev-parse HEAD)" --status completed --limit 1

# start the release by pushing the version tag
git push origin HEAD:refs/tags/1.9.21

# follow the release workflow until it finishes
gh run watch "$(gh run list --workflow release.yml --event push --limit 1 --json databaseId -q '.[0].databaseId')"
```

Pushing the tag with `HEAD:refs/tags/…` avoids creating a local tag, which would become stale
once the workflow moves the tag onto the release commit. Equivalently, you can run the workflow
without pushing a tag yourself: `gh workflow run release.yml -R skiptools/skip -f version=1.9.21`
releases the head of `main`.

When the workflow has finished, update your checkout with the release commit and the moved tag:

```console
git pull
git fetch --tags --force
```

### Releasing from the GitHub web UI

1. Open the [Actions tab](https://github.com/skiptools/skip/actions), and check that the most
   recent runs of **skip ci** and **skipstone CI** for the latest commit on `main` succeeded.
   If either has not run for that commit, select the workflow, click **Run workflow**, choose
   `main`, and wait for it to pass.
1. Select the [**skip release**](https://github.com/skiptools/skip/actions/workflows/release.yml)
   workflow and click **Run workflow**.
1. Leave **Use workflow from** set to `main`, enter the version (e.g. `1.9.21`) in the
   **Version to release** field, and leave **Release even if CI has not passed** unchecked.
1. Click **Run workflow**, and follow the run until it finishes.

> [!WARNING]
> Do not use **Releases → Draft a new release** to make a release. That creates the tag and the
> release without the `skip-macos.zip` and `skip-linux.zip` artifacts, and the release workflow
> then refuses to run for a version whose release already exists. If this happens, delete the
> release and its tag (`gh release delete 1.9.21 -R skiptools/skip --cleanup-tag`) and use one
> of the methods above.

The **Version to release** field must be filled in: leaving it empty performs a dry run that
releases nothing. The **Release even if CI has not passed** option skips the CI check, and is only
meant for shipping an urgent fix when CI is failing for reasons unrelated to the release.

### After the release

1. **Check the results:** the [release](https://github.com/skiptools/skip/releases) has both
   artifactbundles attached, `main` has the "Release X.Y.Z" commit, and
   [homebrew-skip](https://github.com/skiptools/homebrew-skip/commits/main) has a matching
   "Release X.Y.Z" commit (`brew update && brew upgrade --cask skip` picks it up).
1. **Update the Homebrew formula.** The [`skip` formula](https://formulae.brew.sh/formula/skip) in
   homebrew-core builds the tool from source, and is updated by a pull request to
   [Homebrew/homebrew-core](https://github.com/Homebrew/homebrew-core), which can be opened with
   `brew bump-formula-pr --strict skip --version=1.9.21`. Note that the first release after
   skipstone was merged into this repository also needs the formula's `url`, `head`, `license`,
   and `install` updated for the new layout, so that pull request must be made by hand.
1. **Smoke test:** run `skip checkup --native` on your own machine with the released version.

If a release fails, look at which steps completed before retrying. A failure before the
"Release X.Y.Z" commit was pushed changes nothing, so you can fix the problem, delete the tag if you
pushed one (`git push origin :refs/tags/1.9.21`), and start again. After that commit is on `main`,
starting the release again for the head of `main` only reports that there is nothing to do (and
re-running the failed workflow run would make a second release commit that is not on `main`), so
the remaining steps (moving the tag, creating the GitHub release, and updating the cask) must be
finished by hand.

### Dry runs

Every night the release workflow performs a dry run. It builds both artifactbundles from the head
of `main` and shows the changes that a release would make, without committing, tagging, pushing, or
publishing anything, so that breakage of the release build is noticed before a release is
attempted. You can start one at any time by running the **skip release** workflow with an empty
**Version to release**, or with `gh workflow run release.yml -R skiptools/skip`.

A dry run can also be performed locally from the repository root:

```console
DRY_RUN=1 ./skipstone/scripts/release_skip.sh
```

This needs the [`swiftly`](https://www.swift.org/install/macos/swiftly/) tool and the
[static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html)
installed, since it cross-compiles the tool for Linux. Running the script locally without
`DRY_RUN=1` stops with an error rather than making a release; it can be overridden with
`SKIP_RELEASE_ALLOW_LOCAL=1`, but releases should be made by the workflow.

The workflow runs against the repository that it was started in, so a fork of skip can rehearse
the whole release process against its own releases (with its own `RELEASE_TOKEN` and fork of
homebrew-skip, if it has them).

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
