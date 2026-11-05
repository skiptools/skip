<p align="center">
  <a href="https://skip.dev">
    <img src="https://assets.skip.dev/images/skipicon.svg" alt="Skip" height="80">
  </a>
</p>

<h3 align="center">One Swift Codebase. Two Native Platforms.</h3>

<p align="center">
  Write your app in Swift and SwiftUI. Skip compiles it natively for iOS and produces real Jetpack Compose for Android.
</p>

<p align="center">
  <a href="https://github.com/skiptools/skip/actions/workflows/ci.yml"><img src="https://github.com/skiptools/skip/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/skiptools/skip/releases/latest"><img src="https://img.shields.io/github/v/release/skiptools/skip?label=version" alt="Latest Release"></a>
  <a href="https://skip.dev/slack"><img src="https://img.shields.io/badge/slack-chat-informational.svg?label=Slack&logo=slack" alt="Slack"></a>
  <a href="https://forums.skip.dev"><img src="https://img.shields.io/badge/forums-discuss-informational.svg?label=Forums&logo=discourse" alt="Forums"></a>
</p>

<p align="center">
  <a href="https://skip.dev/docs/gettingstarted/">Getting Started</a> · <a href="https://skip.dev/docs/">Documentation</a> · <a href="https://skip.dev/blog/">Blog</a> · <a href="https://github.com/skiptools/skip/issues">Issues</a>
</p>

---

<p align="center">
  <a href="https://assets.skip.dev/screens/swift-sdk-for-android-in-action-showcase.png">
    <img src="https://assets.skip.dev/screens/swift-sdk-for-android-in-action-showcase.png" alt="Skip Showcase running on iOS and Android" width="900">
  </a>
</p>

## What is Skip?

Skip is a free, open-source tool for building native iOS and Android apps from a single Swift codebase. You write your app in Swift and SwiftUI, and Skip produces real Jetpack Compose for Android. Both sides are genuinely native: SwiftUI on iOS, Jetpack Compose on Android. No web views, no custom rendering engine, and no additional runtime.

Skip supports two development modes:

- **Skip Fuse** compiles your Swift natively for Android using the [official Swift SDK for Android](https://www.swift.org/blog/swift-6.3-released/#android). You get the full Swift language, standard library, and Foundation on both platforms, with bridging to call Kotlin and Java APIs when needed.

- **Skip Lite** transpiles your Swift source code to Kotlin, maximizing interoperability with existing Kotlin and Java libraries and the Android ecosystem.

Both modes map SwiftUI to Jetpack Compose using the [SkipUI](https://github.com/skiptools/skip-ui) compatibility framework, so your UI is native on each platform.

### Why Skip?

- **No new language to learn.** If you know Swift and SwiftUI, you already know how to build for Android with Skip. Other cross-platform tools ask you to write JavaScript, Dart, or Kotlin. Skip lets you keep writing Swift.

- **Truly native on both platforms.** Skip produces real SwiftUI on iOS and real Jetpack Compose on Android. Users get the native look, feel, and performance they expect.

- **Full ecosystem access.** Skip apps can use Swift packages on both platforms, and can call Kotlin/Java APIs directly on Android. Over 2,200 Swift packages already build for Android, as tracked at the [Swift Package Index](https://swiftpackageindex.com/search?query=platform%3Aandroid).

- **No lock-in.** Skip builds on the officially supported Swift SDK for Android. Your Swift code, packages, and skills work on Android with or without Skip.

- **Free and open source.** Skip is complete free and developed independently from any parent corporation, funded by [your sponsorship](https://skip.dev/sponsor/).

### Skip versus {Flutter/React Native/Compose Multiplatform/MAUI/etc.}

Choosing a technology to help you build an app for iOS and Android from a single codebase can be a make-or-break decision. Everyone knows a bad app or a crummy port within moments of launching the app, and consumers are ruthless in deleting bloated, slow, or "weird-feeling" apps within moments.

You can read our own assessment of Skip's strengths at [skip.dev/compare/](https://skip.dev/compare/).

## Quick Start

Install Skip with [Homebrew](https://brew.sh), verify your environment, and create your first project:

```shell
brew tap skiptools/skip
brew install skip
skip checkup
skip create
```

Your project will be created and opened in Xcode. Run it against an iPhone simulator, and Skip will automatically build and launch the Android version on a running emulator at the same time.

For the full setup guide, see [Getting Started](https://skip.dev/docs/gettingstarted/).

### Native Android Compilation (Skip Fuse)

To build apps that compile Swift natively for Android, install the Swift Android SDK:

```shell
skip android sdk install
```

Then create a native app project:

```shell
skip init --native-app --appid=com.example.myapp my-app MyApp
```

See the [Fuse mode documentation](https://skip.dev/docs/modes/) for details on how native compilation and Kotlin bridging work.

## Sample Apps

Skip ships with several sample applications that demonstrate different features and patterns. All are open source and available in the [skiptools](https://github.com/skiptools) organization.

### Skip Showcase

A comprehensive catalog of SwiftUI components running side by side on iOS and Android. The best way to see how Skip maps SwiftUI to Jetpack Compose.

<p align="center">
  <a href="https://play.google.com/store/apps/details?id=org.appfair.app.Showcase"><img src="https://assets.skip.dev/badges/google-play-store.svg" alt="Google Play Store" height="50"></a>
  <a href="https://apps.apple.com/us/app/skip-showcase/id6474885022"><img src="https://assets.skip.dev/badges/apple-app-store.svg" alt="Apple App Store" height="50"></a>
</p>

- **Source:** [skipapp-showcase-fuse](https://github.com/skiptools/skipapp-showcase-fuse) (Fuse) · [skipapp-showcase](https://github.com/skiptools/skipapp-showcase) (Lite)

### More Samples

| App | Description | Mode |
|-----|-------------|------|
| [skipapp-hello](https://github.com/skiptools/skipapp-hello) | Minimal starter app with a tab view and list | Lite |
| [skipapp-howdy](https://github.com/skiptools/skipapp-howdy) | Starter app for Skip Fuse | Fuse |
| [skipapp-fireside](https://github.com/skiptools/skipapp-fireside) | Firebase integration demo | Lite |
| [skipapp-fireside-fuse](https://github.com/skiptools/skipapp-fireside-fuse) | Firebase integration demo | Fuse |
| [skipapp-bookings-fuse](https://github.com/skiptools/skipapp-bookings-fuse) | Travel bookings with maps and Compose views | Fuse |
| [skipapp-weather](https://github.com/skiptools/skipapp-weather) | Weather app with async networking | Lite |
| [skipapp-calculatrix](https://github.com/skiptools/skipapp-calculatrix) | Calculator with custom layout | Lite |
| [skipapp-lottiedemo](https://github.com/skiptools/skipapp-lottiedemo) | Lottie animation playback | Lite |
| [skipapp-travelposters-native](https://github.com/skiptools/skipapp-travelposters-native) | Shared Swift model with native UI on each platform | Fuse |

Browse all sample apps at [skip.dev/docs/samples](https://skip.dev/docs/samples/).

## Framework Libraries

Skip provides a suite of open-source libraries that implement standard Apple frameworks for Android, so your existing Swift code works across platforms.

### Core Frameworks

| Library | Description |
|---------|-------------|
| [skip-foundation](https://github.com/skiptools/skip-foundation) | Foundation APIs (URL, Data, Date, JSON, FileManager, etc.) |
| [skip-model](https://github.com/skiptools/skip-model) | Observation and Combine (backed by Compose MutableState) |
| [skip-ui](https://github.com/skiptools/skip-ui) | SwiftUI to Jetpack Compose |
| [skip-fuse](https://github.com/skiptools/skip-fuse) | Fuse mode umbrella (OSLog, Observable, AnyDynamicObject) |
| [skip-fuse-ui](https://github.com/skiptools/skip-fuse-ui) | Native SwiftUI on Android for Fuse mode |
| [skip-bridge](https://github.com/skiptools/skip-bridge) | Bidirectional Swift-Kotlin interop |
| [skip-lib](https://github.com/skiptools/skip-lib) | Swift standard library extensions |
| [skip-unit](https://github.com/skiptools/skip-unit) | XCTest to JUnit mapping |

### Integration Frameworks

| Library | Description |
|---------|-------------|
| [skip-firebase](https://github.com/skiptools/skip-firebase) | Firebase (Auth, Firestore, Messaging, Analytics, etc.) |
| [skip-sql](https://github.com/skiptools/skip-sql) | SQLite database access |
| [skip-keychain](https://github.com/skiptools/skip-keychain) | Keychain / EncryptedSharedPreferences |
| [skip-web](https://github.com/skiptools/skip-web) | WKWebView / android.webkit.WebView |
| [skip-av](https://github.com/skiptools/skip-av) | AVKit / ExoPlayer |
| [skip-device](https://github.com/skiptools/skip-device) | Network, Location, Sensors |
| [skip-motion](https://github.com/skiptools/skip-motion) | Lottie animations |
| [skip-ffi](https://github.com/skiptools/skip-ffi) | C/C++ interop via JNA |

See the full module documentation at [skip.dev/docs/modules](https://skip.dev/docs/modules/).

## Architecture

The [skip](https://github.com/skiptools/skip) repository hosts the Skip SwiftPM build plugin, which integrates with Xcode and Swift Package Manager to drive the Android build alongside your normal iOS build. It works together with [skipstone](https://github.com/skiptools/skipstone), the binary that powers both the `skip` CLI and the plugin.

For more on how Skip projects are structured, see:

- [Project Types](https://skip.dev/docs/project-types/) - App and library project structures
- [Lite and Fuse Modes](https://skip.dev/docs/modes/) - Transpilation vs. native compilation
- [CLI Reference](https://skip.dev/docs/skip-cli/) - Full command-line tool documentation

## Documentation

| Resource | Link |
|----------|------|
| Getting Started | [skip.dev/docs/gettingstarted](https://skip.dev/docs/gettingstarted/) |
| Full Documentation | [skip.dev/docs](https://skip.dev/docs/) |
| Blog | [skip.dev/blog](https://skip.dev/blog/) |
| Module Reference | [skip.dev/docs/modules](https://skip.dev/docs/modules/) |
| Sample Apps | [skip.dev/docs/samples](https://skip.dev/docs/samples/) |
| Component Gallery | [skip.dev/docs/components](https://skip.dev/docs/components/) |
| CLI Reference | [skip.dev/docs/skip-cli](https://skip.dev/docs/skip-cli/) |
| Competitor analysis | [skip.dev/compare/](https://skip.dev/compare/) |

## Community

- **Forums:** [forums.skip.dev](https://forums.skip.dev) - Discussions, questions, and announcements
- **Slack:** [skip.dev/slack](https://skip.dev/slack/) - Real-time chat with the Skip team and community
- **Issues:** [github.com/skiptools/skip/issues](https://github.com/skiptools/skip/issues) - Bug reports and feature requests
- **Mastodon:** [@skiptools@mas.to](https://mas.to/@skiptools)
