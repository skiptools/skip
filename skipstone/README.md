# SkipSource

Swift Kotlin Interop




SkipBuild
========

A "Skip Package" is a set of conventions that defines a package
that includes buildable artifacts for both:

- Swift Package Manager (SPM) Projects
- Gradle Kotlin Projects

SkipUnit is the base class for executing the transpilation of sources and tests.

## Build Phases

### App

1. Use `plugins { id("com.android.application") }` in `build.gradle.kts`
1. Info.plist -> AndroidManifest.xml

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

