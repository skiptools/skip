SkipBuild
========

A "Skip Package" is a set of conventions that defines a package
that includes buildable artifacts for both:

- Swift Package Manager (SPM) Projects
- Gradle Kotlin Projects

SkipUnit is the base class for executing the transpilation of sources and tests.

## Build PlugIns

### App

1. Use `plugins { id("com.android.application") }` in `build.gradle.kts`

### Resources

1. Copy data resources into Android.res
1. Generate symbolic constants for strings?
1. Convert Foundation.NSLocalizedString to lookup
1. Convert SwiftUI.Text and SwiftUI.LocalizedStringKey to lookup (handling interpolation)

### Testing -> junit

1. Convert "XCTestCase" superclass to "junit.Test"
1. Add @Test annotation to all "fun test" functions
    
### Codable -> kotlinx.serialization.json

1. Add @Serializable annotation to encodable classes
1. Use `json = kotlinx.serialization.json.Json.encodeToString(ob)`
1. Use `ob = kotlinx.serialization.json.Json.decodeFromString<Ob>(json)`

### Compose -> androidx.compose.ui

1. Add dependency `implementation("androidx.compose.ui:ui:$composeUIVersion")`
1. Add `android { buildFeatures { compose = true } }` to `build.gradle.kts`

### Async -> kotlinx.coroutines

1. Add dependency `implementation("org.jetbrains.kotlinx:kotlinx-coroutines:$coroutinesVersion")`
1. Add `android { buildFeatures { compose = true } }` to `build.gradle.kts`

### Testing async -> org.jetbrains.kotlinx:kotlinx-coroutines-test

1. Add `testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:$coroutinesVersion")`
1. Convert async tests to use [runTest](https://kotlin.github.io/kotlinx.coroutines/kotlinx-coroutines-test/kotlinx.coroutines.test/run-test.html)


## Generate File System Layout

### Single-Module Project

A simple single-module project named `GreatCode` with a single Kotlin file
and single test case will be output the the destination
folder (e.g., `kip/GreatCodeTests.GreatCodeTest`) with
a mostly-standard gradle/kotlin layout.

The source layout:

```
.
├── Package.swift
├── Sources
│   └── GreatCode
│       └── GreatCode.swift
└── Tests
    └── GreatCodeTests.swift
        └── GreatCodeTests.swift

```

Will translate to:


```
.
├── GreatCode
│   ├── build.gradle.kts
│   └── src
│       ├── main
│       │   └── kotlin
│       │       └── GreatCode
│       │           └── GreatCode.kt
│       └── test
│           └── kotlin
│               └── GreatCode
│                   └── GreatCodeTests.kt
├── build.gradle.kts
├── gradle
│   └── wrapper
│       ├── gradle-wrapper.jar
│       └── gradle-wrapper.properties
├── gradle.properties
├── gradlew
└── settings.gradle.kts
```



### Multi-Module Project

A Swift `Package.swift` with multiple modules will be translated into a
[Gradle multi-project build](https://docs.gradle.org/current/userguide/multi_project_builds.html#sec:creating_multi_project_builds).

Given the following `Package.swift`:

```swift
import PackageDescription

let package = Package(
    name: "MultiModule",
    platforms: [
        .macOS(.v12),
        .iOS(.v16),
    ],
    products: [
        .library(name: "SkipFoundation", targets: ["SkipFoundation"]),
        .library(name: "SkipUI", targets: ["SkipUI"]),
        .library(name: "SkipDemoLib", targets: ["SkipDemoLib"]),
        .library(name: "SkipDemoApp", targets: ["SkipDemoApp"]),
    ],
    targets: [
        .target(name: "SkipFoundation", dependencies: []),
        .target(name: "SkipUI", dependencies: ["SkipFoundation"]),
        .target(name: "SkipDemoLib", dependencies: ["SkipFoundation"]),
        .target(name: "SkipDemoApp", dependencies: ["SkipDemoLib", "SkipUI"]),
        
        .testTarget(name: "SkipFoundationTests", dependencies: ["SkipFoundation"]),
        .testTarget(name: "SkipUITests", dependencies: ["SkipUI"]),
        .testTarget(name: "SkipDemoAppTests", dependencies: ["SkipDemoApp"]),
        .testTarget(name: "SkipDemoLibTests", dependencies: ["SkipDemoLib"]),
    ]
)
```


The following Gradle project structure will be generated.

```
.
├── SkipDemoApp
│   ├── build.gradle.kts
│   └── src
│       ├── main
│       │   └── kotlin
│       │       └── SkipDemoApp
│       │           ├── ContentView.kt
│       │           └── SkipDemoApp.kt
│       └── test
│           └── kotlin
│               └── SkipDemoApp
│                   └── SkipDemoAppTests.kt
├── SkipDemoLib
│   ├── build.gradle.kts
│   └── src
│       ├── main
│       │   └── kotlin
│       │       └── SkipDemoLib
│       │           ├── CellularAutomaton.kt
│       │           └── SkipDemoLib.kt
│       └── test
│           └── kotlin
│               └── SkipDemoLib
│                   └── SkipDemoLibTests.kt
├── SkipFoundation
│   ├── build.gradle.kts
│   └── src
│       ├── main
│       │   └── kotlin
│       │       └── SkipFoundation
│       │           └── SkipFoundation.kt
│       └── test
│           └── kotlin
│               └── SkipFoundation
│                   └── SkipFoundationTests.kt
├── SkipUI
│   ├── build.gradle.kts
│   └── src
│       ├── main
│       │   └── kotlin
│       │       └── SkipUI
│       │           └── SkipUI.kt
│       └── test
│           └── kotlin
│               └── SkipUI
│                   └── SkipUITests.kt
├── build.gradle.kts
├── gradle
│   └── wrapper
│       ├── gradle-wrapper.jar
│       └── gradle-wrapper.properties
├── gradle.properties
├── gradlew
└── settings.gradle.kts
```

For this project, the `settings.gradle.kts` will include each of the modules and look something like:

```kotlin
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

val modules = file("modules").listFiles().filter { it.isDirectory }.map { it.name }
for (module in modules) {
    include("modules:$module")
}
```

The individual module `build.gradle.kts` files will have dependencies that match
the inter-module dependencies in the `Package.swift` file.

For example, `SkipDemoApp` depends on `SkipDemoLib` and `SkipUI`,
both of which depend on `SkipFoundation`.

`SkipDemoLib/build.gradle.kts`'s dependecies will include just the one dependency:

```kotlin
dependencies {
    implementation(project(":SkipFoundation"))
}
```

And `SkipDemoApp/build.gradle.kts`'s dependecies will reference all the dependencies:

```kotlin
dependencies {
    implementation(project(":SkipDemoLib"))
    implementation(project(":SkipFoundation"))
    implementation(project(":SkipUI"))
}
```

## Q: Output package name?


## Q: Names?

SkipPack
SkipPackaging
SkipCraft
SkipGen
SkipPackager
SkipKit
SkipAndroid
SkipDroid
SkipStudio
SkipGradle
SkipGrad
SkipIntegration
SkipInteg
SkipFlow
SkipPing
SkipJack
SkipBuild
SkipPipeline
SkipPipe
Skipper
Skipple
SkipIntake
SkipProcessing
SkipSet
Skip
SkipBuild
Skippiks
Skippi
SkipToMyLou
Crave (2Gradle)

