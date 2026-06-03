// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

@testable import SkipBuild
import SkipSyntax
import SwiftSyntax
import Universal
import XCTest
#if canImport(SkipDriveExternal)
import SkipDriveExternal // for AppBuildGradleAGPIssue
#endif

final class SkipConfigTests: XCTestCase {
    func expectGradle(yaml configYAMLs: String, gradle expectedGradle: String, line: UInt = #line) throws {
        //if expectedGradle.isEmpty { return }
        //print("CHECKING YAML:", configYAMLs, separator: "\n")
        let yamls = try YAML.parse(yamls: configYAMLs)
        guard var config = try yamls.first?.json() else {
            return XCTFail("no YAML in arg")
        }
        for yaml in yamls.dropFirst() {
            try config.merge(with: yaml.json())
        }

        //print("AS JSON:", try config.prettyJSON, separator: "\n")
        let project = try config.decode() as GradleBlock
        let gradle = project.generate()
        //print("AGAINST GRADLE:", gradle, separator: "\n")
        XCTAssertEqual(expectedGradle.trimmingCharacters(in: .whitespacesAndNewlines), gradle.trimmingCharacters(in: .whitespacesAndNewlines), line: line)
    }

    /// build up the sample from: https://github.com/gradle/native-samples/blob/master/build.gradle.kts
    func testSimplePluginGradle() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'plugins'
            contents:
              - 'id("org.gradle.samples.wrapper")'
        """, gradle: """
        plugins {
            id("org.gradle.samples.wrapper")
        }
        """)
    }

    func testMergedGradle() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'plugins'
            contents:
              - 'id("org.gradle.samples.plugin1")'
        ---
        contents:
          - block: 'plugins'
            contents:
              - 'id("org.gradle.samples.plugin2")'
              - 'id("org.gradle.samples.plugin3")'
        """, gradle: """
        plugins {
            id("org.gradle.samples.plugin1")
            id("org.gradle.samples.plugin2")
            id("org.gradle.samples.plugin3")
        }
        """)
    }


    func testMergedGradleMultiSection() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'plugins'
            contents:
              - 'id("org.gradle.samples.plugin1")'
          - block: 'dependencies'
            contents:
              - 'implementation("androidx.appcompat:appcompat:1.2.0")'
              - 'implementation("com.google.android.material:material:1.2.0")'
              - 'implementation("androidx.constraintlayout:constraintlayout:2.0.4")'
        ---
        contents:
          # add a plugin
          - block: 'plugins'
            contents:
              - 'id("org.gradle.samples.plugin2")'

          # add some more dependencies
          - block: 'dependencies'
            contents:
              - 'testImplementation("junit:junit:4.13.1")'
              - 'androidTestImplementation("androidx.test.ext:junit:1.1.2")'
              - 'androidTestImplementation("androidx.test.espresso:espresso-core:3.3.0")'

          # add another plug-in
          - block: 'plugins'
            contents:
              - 'id("org.gradle.samples.plugin3")'
        """, gradle: """
        plugins {
            id("org.gradle.samples.plugin1")
            id("org.gradle.samples.plugin2")
            id("org.gradle.samples.plugin3")
        }

        dependencies {
            implementation("androidx.appcompat:appcompat:1.2.0")
            implementation("com.google.android.material:material:1.2.0")
            implementation("androidx.constraintlayout:constraintlayout:2.0.4")
            testImplementation("junit:junit:4.13.1")
            androidTestImplementation("androidx.test.ext:junit:1.1.2")
            androidTestImplementation("androidx.test.espresso:espresso-core:3.3.0")
        }
        """)
    }


    /// build up the sample from: https://docs.gradle.org/current/userguide/third_party_integration.html#sec:embedding_quickstart
    func testSampleQuickstartGradle() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'repositories'
            contents:
              - 'maven { url = uri("https://repo.gradle.org/gradle/libs-releases") }'
          - block: 'dependencies'
            contents:
              - 'implementation("org.gradle:gradle-tooling-api:$toolingApiVersion")'
              - '// The tooling API need an SLF4J implementation available at runtime, replace this with any other implementation'
              - 'runtimeOnly("org.slf4j:slf4j-simple:1.7.10")'

        """, gradle: """
        repositories {
            maven { url = uri("https://repo.gradle.org/gradle/libs-releases") }
        }

        dependencies {
            implementation("org.gradle:gradle-tooling-api:$toolingApiVersion")
            // The tooling API need an SLF4J implementation available at runtime, replace this with any other implementation
            runtimeOnly("org.slf4j:slf4j-simple:1.7.10")
        }
        """)

    }

    /// build up the sample from: https://docs.gradle.org/current/samples/sample_building_android_apps.html
    func testSampleAndroidGradle() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'plugins'
            contents:
              - 'id("com.android.application") version "7.3.0"'
          - block: 'repositories'
            contents:
              - 'google()'
              - 'mavenCentral()'
          - block: 'android'
            contents:
              - 'compileSdkVersion(30)'
              - block: 'defaultConfig'
                contents:
                  - 'applicationId = "org.gradle.samples"'
                  - 'minSdkVersion(16)'
                  - 'targetSdkVersion(30)'
                  - 'versionCode = 1'
                  - 'versionName = "1.0"'
                  - 'testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"'
              - block: 'buildTypes'
                contents:
                  - block: 'getByName'
                    param: '"release"'
                    contents:
                      - 'isMinifyEnabled = false'
                      - 'proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'
          - block: 'dependencies'
            contents:
              - 'implementation("androidx.appcompat:appcompat:1.2.0")'
              - 'implementation("com.google.android.material:material:1.2.0")'
              - 'implementation("androidx.constraintlayout:constraintlayout:2.0.4")'
              - 'testImplementation("junit:junit:4.13.1")'
              - 'androidTestImplementation("androidx.test.ext:junit:1.1.2")'
              - 'androidTestImplementation("androidx.test.espresso:espresso-core:3.3.0")'

        """, gradle: """
        plugins {
            id("com.android.application") version "7.3.0"
        }

        repositories {
            google()
            mavenCentral()
        }

        android {
            compileSdkVersion(30)
            defaultConfig {
                applicationId = "org.gradle.samples"
                minSdkVersion(16)
                targetSdkVersion(30)
                versionCode = 1
                versionName = "1.0"
                testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
            }
            buildTypes {
                getByName("release") {
                    isMinifyEnabled = false
                    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
                }
            }
        }

        dependencies {
            implementation("androidx.appcompat:appcompat:1.2.0")
            implementation("com.google.android.material:material:1.2.0")
            implementation("androidx.constraintlayout:constraintlayout:2.0.4")
            testImplementation("junit:junit:4.13.1")
            androidTestImplementation("androidx.test.ext:junit:1.1.2")
            androidTestImplementation("androidx.test.espresso:espresso-core:3.3.0")
        }
        """)


    }

    // MARK: - merge: prepend (leaf-wins for first-call-wins DSLs)

    /// Sanity check that the default merge mode (no `merge:` field) keeps the existing
    /// append behavior, where the second YAML document's contents are emitted after the
    /// first's. This is a regression guard for the targeted-prepend change.
    func testMergedGradleDefaultAppend() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                contents:
                  - 'version("android-sdk-min", "28")'
        ---
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                contents:
                  - 'version("android-sdk-min", "26")'
        """, gradle: """
        versionCatalogs {
            create("libs") {
                version("android-sdk-min", "28")
                version("android-sdk-min", "26")
            }
        }
        """)
    }

    /// With `merge: 'prepend'` declared on the dependent-side block, the leaf module's
    /// later-merged entries are emitted *before* the dependent's earlier entries — so the
    /// leaf's `version("android-sdk-min", "26")` appears first in the generated DSL and
    /// wins in Gradle's first-call-wins version catalog.
    func testMergedGradlePrependOnDependent() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                merge: 'prepend'
                contents:
                  - 'version("android-sdk-min", "28")'
        ---
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                contents:
                  - 'version("android-sdk-min", "26")'
        """, gradle: """
        versionCatalogs {
            create("libs") {
                version("android-sdk-min", "26")
                version("android-sdk-min", "28")
            }
        }
        """)
    }

    /// Declaring `merge: 'prepend'` on the leaf-side block produces the same result as
    /// declaring it on the dependent side. Either side opting into prepend is enough.
    func testMergedGradlePrependOnLeaf() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                contents:
                  - 'version("android-sdk-min", "28")'
        ---
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                merge: 'prepend'
                contents:
                  - 'version("android-sdk-min", "26")'
        """, gradle: """
        versionCatalogs {
            create("libs") {
                version("android-sdk-min", "26")
                version("android-sdk-min", "28")
            }
        }
        """)
    }

    /// The `merge: prepend` flag is scoped to the block that declares it. A sibling
    /// `dependencies` block — which uses last-wins / order-irrelevant DSL semantics —
    /// must keep its default append behavior so leaf overrides of property assignments
    /// (like `minSdk = …`) and dependency declarations continue to work.
    func testMergedGradlePrependDoesNotAffectSiblings() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                merge: 'prepend'
                contents:
                  - 'version("android-sdk-min", "28")'
          - block: 'dependencies'
            contents:
              - 'implementation("dep-from-base")'
          - block: 'android'
            contents:
              - block: 'defaultConfig'
                contents:
                  - 'minSdk = 31'
        ---
        contents:
          - block: 'versionCatalogs'
            contents:
              - block: 'create("libs")'
                contents:
                  - 'version("android-sdk-min", "26")'
          - block: 'dependencies'
            contents:
              - 'implementation("dep-from-leaf")'
          - block: 'android'
            contents:
              - block: 'defaultConfig'
                contents:
                  - 'minSdk = 26'
        """, gradle: """
        versionCatalogs {
            create("libs") {
                version("android-sdk-min", "26")
                version("android-sdk-min", "28")
            }
        }

        dependencies {
            implementation("dep-from-base")
            implementation("dep-from-leaf")
        }

        android {
            defaultConfig {
                minSdk = 31
                minSdk = 26
            }
        }
        """)
    }

    /// `merge: prepend` composes cleanly with `remove:` — the leaf module's explicit removal
    /// still strips the targeted dependent-side line, and the surviving entries are emitted
    /// with the leaf's contributions prepended ahead of the dependent's defaults.
    func testMergedGradlePrependRespectsRemove() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'create("libs")'
            merge: 'prepend'
            contents:
              - 'version("android-sdk-min", "28")'
              - 'version("android-sdk-compile", "36")'
        ---
        contents:
          - block: 'create("libs")'
            remove: ['version("android-sdk-compile", "36")']
            contents:
              - 'version("android-sdk-compile", "35")'
        """, gradle: """
        create("libs") {
            version("android-sdk-compile", "35")
            version("android-sdk-min", "28")
        }
        """)
    }

    /// `merge: prepend` is sticky across a chain of three or more layered merges. Even when
    /// only the deepest dependent declares `merge: 'prepend'`, the leaf's entries still end
    /// up first, with each intervening module's entries inserted ahead of the modules deeper
    /// than it. This models a realistic skip-unit → skip-foundation → skip-ui → app chain
    /// where only skip-unit's `create("libs")` carries the flag.
    func testMergedGradlePrependStickyAcrossChain() throws {
        try expectGradle(yaml: """
        contents:
          - block: 'create("libs")'
            merge: 'prepend'
            contents:
              - 'version("v", "from-deepest")'
        ---
        contents:
          - block: 'create("libs")'
            contents:
              - 'version("v", "from-middle")'
        ---
        contents:
          - block: 'create("libs")'
            contents:
              - 'version("v", "from-leaf")'
        """, gradle: """
        create("libs") {
            version("v", "from-leaf")
            version("v", "from-middle")
            version("v", "from-deepest")
        }
        """)
    }

#if canImport(SkipDriveExternal)
    /// Verify detection and `--fix` removal of AGP-incompatible settings in an app's build.gradle.kts.
    func testAppBuildGradleAGPIssues() throws {
        // a fresh project: the kotlin.android plugin appears only as a commented-out template hint, so there
        // are no *active* AGP issues and a fix must leave the file unchanged (no false positives)
        let clean = """
        plugins {
            alias(libs.plugins.kotlin.compose)
            alias(libs.plugins.android.application)
            id("skip-build-plugin")
        }
        android {
            buildTypes {
                getByName("release") {
                    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
                }
            }
        }
        """
        XCTAssertEqual(0, AppBuildGradleAGPIssue.issues(inAppBuildGradle: clean).count)
        XCTAssertEqual(clean, AppBuildGradleAGPIssue.removingIssues(fromAppBuildGradle: clean))

        // a build.gradle.kts with both incompatibilities: the kotlin.android plugin and the default proguard file
        let problematic = """
        plugins {
            alias(libs.plugins.android.application)
            alias(libs.plugins.kotlin.android)
            alias(libs.plugins.kotlin.compose)
        }
        android {
            buildTypes {
                getByName("release") {
                    proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
                }
            }
        }
        """
        let issues = AppBuildGradleAGPIssue.issues(inAppBuildGradle: problematic)
        XCTAssertEqual(2, issues.count)
        // every issue message links to the support forum
        for issue in issues {
            XCTAssertTrue(issue.message.contains("https://forums.skip.dev/categories/announcements"), "issue should link to the forum: \(issue.message)")
        }

        // fixing removes the getDefaultProguardFile section (keeping proguard-rules.pro) and the kotlin.android line
        let fixed = AppBuildGradleAGPIssue.removingIssues(fromAppBuildGradle: problematic)
        XCTAssertEqual(fixed, """
        plugins {
            alias(libs.plugins.android.application)
            alias(libs.plugins.kotlin.compose)
        }
        android {
            buildTypes {
                getByName("release") {
                    proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
                }
            }
        }
        """)
        // the fixed contents no longer trigger any issues
        XCTAssertEqual(0, AppBuildGradleAGPIssue.issues(inAppBuildGradle: fixed).count)
    }
#endif
}
