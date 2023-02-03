
SkipPack
========

A "Skip Package" is a set of conventions that defines a package
that includes buildable artifacts for both:

    - Swift Package Manager (SPM) Projects
    - Gradle Kotlin Projects


## Q: what should the file system layout look for a skipped Swift/Kotlin library?


### Option 1: Conventional SPM + conventional Gradle

Swift files are placed in SPM-idiomatic `Sources/ModuleName/*.swift`
and Kotlin files are placed in their own Gradle/Maven-idiomatic location: `src/main/java/package…names/*.kt`.
The necessary gradle build files (`build.gradle.kts`, `settings.gradle.kts`, `gradle.properties`) are output at the root folder so that runnint `gradle build` works out of the box.


```
.
├── Package.swift
├── README.md
├── Sources
│   └── CrossFoundation
│       ├── CrossFoundation.swift
│       ├── Data.swift
│       ├── Date.swift
│       ├── FileManager.swift
│       ├── JSON.swift
│       ├── ProcessInfo.swift
│       ├── Random.swift
│       ├── URL.swift
│       └── UUID.swift
├── Tests
│   └── CrossFoundationTests
│       └── CrossFoundationTests.swift
├── build.gradle.kts
├── gradle.properties
├── settings.gradle.kts
└── src
    ├── androidTest
    │   └── java
    │       └── com
    │           └── CrossFoundation
    │               └── CrossFoundationInstrumentedTest.kt
    ├── main
    │   └── java
    │       └── com
    │           └── CrossFoundation
    │               ├── CrossFoundation.kt
    │               ├── Data.kt
    │               ├── Date.kt
    │               ├── FileManager.kt
    │               ├── JSON.kt
    │               ├── ProcessInfo.kt
    │               ├── URL.kt
    │               ├── UUID.kt
    │               └── Random.kt
    └── test
        └── java
            └── com
                └── CrossFoundation
                    └── CrossFoundationTests.kt
```

Advantages of this layout:

1. It will be familiar to Swift/SPM developers 
1. It will be familiar to Kotlin/Gradle developers 
1. It will be simpler to implement multi-module packages
1. It could be easier to "separate" the two halves of the project if ever needed
    
Disadvantages of this layout:

1. It is tricker to jump to the transpiled Kotlin when trying to debug the derived .kt for a given .swift
1. It creates an overall folder structure that is somewhat alien to everyone
1. What would the package name be? We probably need to retain the case of the original source Swift package (e.g., "CoreFoundation"), so that will always be un-idiomatic Java/Kotlin.




### Option 2: Conventional SPM + unconventional Gradle

This option uses SPM's convention of Sources/ and Tests/ as the
source roots and simply places the peer `.kt` files
next to their equivalent `.swift` files. Additional Kotlin
files can be hand-written in those folders to augment the
transpiled `.kt` files (which will, themselves, always be
overwritten by their peer `.swift` file when the
transpiler is run).

```
.
├── Package.swift
├── README.md
├── Sources
│   └── CrossFoundation
│       ├── CrossFoundation.kt
│       ├── CrossFoundation.swift
│       ├── Data.kt
│       ├── Data.swift
│       ├── Date.kt
│       ├── Date.swift
│       ├── FileManager.kt
│       ├── FileManager.swift
│       ├── JSON.kt
│       ├── JSON.swift
│       ├── ProcessInfo.kt
│       ├── ProcessInfo.swift
│       ├── Random.kt
│       ├── Random.swift
│       ├── URL.kt
│       ├── URL.swift
│       ├── UUID.kt
│       └── UUID.swift
├── Tests
│   └── CrossFoundationTests
│       ├── CrossFoundationTests.kt
│       └── CrossFoundationTests.swift
├── build.gradle.kts
├── gradle.properties
└── settings.gradle.kts
```

Advantages of this layout:

1. It will be very familiar to Swift developers
1. It doesn't introduce additional weird src/test/java/com/example… folders
1. It will be clear where to look to debug the derived Kotlin
1. It is a shallower and simpler folder structure, which makes it easier to understand
    
Disadvantages of this layout:

1. It is unidiomatic for Kotlin/Gradle/Adroid conventions
1. It works OK for single-module builds, but multi-module would be uglier




### Option 3: Unconventional SPM + unconventional Gradle

As SPM is expected to be the "dominant" side of the packaging equatation, 
using an unconventional Swift packaging format was not considered.

