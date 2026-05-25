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
                    proguardFiles("proguard-rules.pro")
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
                    proguardFiles("proguard-rules.pro")
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
                    proguardFiles("proguard-rules.pro")
                }
            }
        }
        """)
        // the fixed contents no longer trigger any issues
        XCTAssertEqual(0, AppBuildGradleAGPIssue.issues(inAppBuildGradle: fixed).count)
    }
#endif
}
