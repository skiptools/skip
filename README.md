# skip

The `skip` plug-in for Swift Package Manager (SPM) 5.7+ transpiles Swift into Koltin.

## Quick Start

Navigate to a folder containing an SPM project with a `Package.swift`,
or create a new one by opening `Terminal.app` and running:

```shell
mkdir SomeSwiftLibrary
cd SomeSwiftLibrary
swift package init
```


Add the following line at the bottom of your `Package.swift` file:

```swift
package.dependencies += [.package(url: "https://github.com/skiptools/skip.git", from: "0.1.10")]
```

Then run:

```shell
alias skip="swift package --disable-sandbox --allow-writing-to-package-directory skip"
skip -version
```

The `skip` alias can be persisted for future `Terminal.app` shell sessions by running:

```shell
echo 'alias skip="swift package --disable-sandbox --allow-writing-to-package-directory skip"' >> ~/.zprofile
```

## System Requirements

macOS 13+ (ARM or Intel), [XCode.app](https://developer.apple.com/xcode/) and [Gradle 8.0+](https://gradle.org/install/#with-a-package-manager).


## Transpilation

For a given package named "SourceModule*Kotlin*", the transpiler takes all the `.swift` source files in the peer "SourceModule" package and transpiles the Swift source files into Kotlin. In addition, module-level `build.gradle.kts` and top-level `settings.gradle.kts` files are emitted, such that the output module source can be built or tested with the `gradle` command.

The output folders for the plug-in are dictated by the build system, and so they differs between Xcode and SPM build. An example resulting folder structure is for the base `SkipLib` and `SkipLibKotlin` packages is:

```
~/Library/Developer/Xcode/DerivedData/Skip-ABC/SourcePackages/plugins/skip-core.output/SkipLibKotlin/SkipTranspilePlugIn
├── SkipLib
│   ├── build.gradle.kts
│   └── src
│       └── main
│           └── kotlin
│               └── skip
│                   └── lib
│                       ├── Array.kt
│                       ├── Dictionary.kt
│                       ├── Error.kt
│                       ├── InOut.kt
│                       ├── Lambda.kt
│                       ├── SkipKotlin.kt
│                       ├── Struct.kt
│                       └── Tuple.kt
└── settings.gradle.kts

```

With SPM plugins, modules have their own independent build output folder, and the plugin can only write to its own output folder. For this reason, when building multiple modules, symbolic links will be created that span between the module output folders and create a consitent and buildable project hierarchy. For example, the `SkipLibTests` and `SkipLibKotlinTests` packages will merge the two transpiled Swift modules into a single Kotlin module using relative links to the peer packages, as seen in the following tree:

```
~/Library/Developer/Xcode/DerivedData/Skip-ABC/SourcePackages/plugins/skip-core.output/SkipLibKotlinTests/SkipTranspilePlugIn
├── SkipLib
│   ├── build.gradle.kts
│   └── src
│       ├── main -> ../../../../SkipLibKotlin/SkipTranspilePlugIn/SkipLib/src/main
│       │   └── kotlin
│       │       └── skip
│       │           └── lib
│       │               ├── Array.kt
│       │               ├── Dictionary.kt
│       │               ├── Error.kt
│       │               ├── InOut.kt
│       │               ├── Lambda.kt
│       │               ├── SkipKotlin.kt
│       │               ├── Struct.kt
│       │               └── Tuple.kt
│       └── test
│           └── kotlin
│               └── skip
│                   └── lib
│                       ├── ArrayTests.kt
│                       ├── DictionaryTests.kt
│                       ├── SkipLibTests.kt
│                       └── StructTests.kt
└── settings.gradle.kts
```


Code that references other modules will be similiarly linked, but at the top level of the module root. Each module added to the `include` list of the generated `seetings.gradle.kts`, so each module will automatically build its dependent modules.

```
~/Library/Developer/Xcode/DerivedData/PKG-ABC/SourcePackages/plugins/skip-template.output/DemoLibKotlinTests/SkipTranspilePlugIn/
├── DemoLib
│   ├── build.gradle.kts
│   └── src
│       ├── main -> ../../../../DemoLibKotlin/SkipTranspilePlugIn/DemoLib/src/main
│       │   └── kotlin
│       │       └── demo
│       │           └── lib
│       │               └── DemoLib.kt
│       └── test
│           └── kotlin
│               └── demo
│                   └── lib
│                       └── DemoLibTests.kt
├── SkipFoundation -> ../../../skip-core.output/SkipFoundationKotlin/SkipTranspilePlugIn/SkipFoundation
│   ├── build.gradle.kts
│   └── src
│       └── main
│           └── kotlin
│               └── skip
│                   └── foundation
│                       ├── Bundle.kt
│                       ├── Calendar.kt
│                       ├── Data.kt
│                       ├── Date.kt
│                       ├── DateFormatter.kt
│                       ├── FileManager.kt
│                       ├── FoundationHelpers.kt
│                       ├── Locale.kt
│                       ├── LocalizedStringResource.kt
│                       ├── NumberFormatter.kt
│                       ├── PropertyListSerialization.kt
│                       ├── Random.kt
│                       ├── SkipFoundation.kt
│                       ├── TimeZone.kt
│                       ├── URL.kt
│                       └── UUID.kt
├── SkipLib -> ../../../skip-core.output/SkipLibKotlin/SkipTranspilePlugIn/SkipLib
│   ├── build.gradle.kts
│   └── src
│       └── main
│           └── kotlin
│               └── skip
│                   └── lib
│                       ├── Array.kt
│                       ├── Dictionary.kt
│                       ├── Error.kt
│                       ├── InOut.kt
│                       ├── Lambda.kt
│                       ├── SkipKotlin.kt
│                       ├── Struct.kt
│                       └── Tuple.kt
├── SkipUnit -> ../../../skip-core.output/SkipUnitKotlin/SkipTranspilePlugIn/SkipUnit
│   ├── build.gradle.kts
│   └── src
│       └── main
│           └── kotlin
│               └── skip
│                   └── unit
│                       ├── SkipUnit.kt
│                       └── XCTest.kt
└── settings.gradle.kts
```

In this case, the `settings.gradle.kts` file will reference each of the linked modules like so:

```kotlin
rootProject.name = "DemoLibTests"

include("SkipLib")
include("SkipFoundation")
include("DemoLib")
include("SkipUnit")
```

