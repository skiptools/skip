@testable import SkipBuild
import SkipSyntax
import SwiftSyntax
import Universal
import XCTest

final class SkipConfigTests: XCTestCase {
    func testMergeJSON() throws {
        XCTAssertEqual(2, try (1 as JSON).merged(with: 2))
        XCTAssertEqual("Y", try ("X" as JSON).merged(with: "Y"))
        XCTAssertEqual("Y", try (1 as JSON).merged(with: "Y"))

        XCTAssertEqual(["A": 1, "B": true], try (["A": 1] as JSON).merged(with: ["B": true]))
        XCTAssertEqual(["A": true], try (["A": 1] as JSON).merged(with: ["A": true]))

        XCTAssertEqual([1, 2, 3], try ([1] as JSON).merged(with: [2, 3]))
        XCTAssertEqual(["A": [1, 2, 1, 2]], try (["A": [1, 2]] as JSON).merged(with: ["A": [1, 2]]))
    }

    func testCreateDSL() async throws {
        /// Parses the given YAML into a `SkipConfig`.
        func cfg(yaml: String) throws -> SkipConfig {
            try YAML.parse(yaml.utf8Data).json().decode()
        }

        XCTAssertEqual(SkipConfig(module: "ModuleName"), try cfg(yaml: """
        module: ModuleName
        """))

        XCTAssertEqual(SkipConfig(module: "ModuleName"), try cfg(yaml: """
        module: 'ModuleName'
        badkey: 'badvalue'
        """))

        let configYAML = """
        # Configuration file for the transpilation process

        # Customized package name
        module: 'CrossSQL'
        package: 'cross.sql'

        gradle:
            - block: android
              dependencies:
                - add: 'implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:+")'
              plugins:
                - add: 'kotlin("plugin.serialization")'
                - add: 'kotlin("plugin.serialization")'

        # Input Swift files to pre-process before being transpiled
        inputs:
            - match: 'SomeUntranspilableSource.swift'
              process: exclude

            - match: '.*Tests.swift'
              process: transform
              steps:
                - name: Remove Empty Comments
                  strip: '^//\\s*$'

        # Output Kotlin files to post-process after being transpiled
        outputs:
          - match: '.*Tests.kt'
            process: transform
            steps:
              - name: 'Fix other names'
                function-name: 'XXX'
                to-function-name: 'YYY'

              - name: 'Fixup Function Names'
                regex: 's;fun test;@Test fun test;g'

              - name: 'Insert Custom Include'
                insert: after-kotlin-imports
                block: |
                  import com.needed.package.*
                  import com.other.needed.package.*

              - name: Append Some Kotlin Include
                insert: after-kotlin-end
                block: |
                  fun someHandyUtility(): String {
                      "GREAT!!"
                  }
        """

        let yaml = try YAML.parse(yaml: configYAML)
        XCTAssertEqual("android", yaml["gradle"]?[0]?["block"])
        XCTAssertEqual(nil, yaml["gradle"]?[0]?["block"]?["dependencies"])
        let config = try cfg(yaml: configYAML)

        XCTAssertEqual("CrossSQL", config.module)
        XCTAssertEqual("cross.sql", config.package)
    }

    func expectGradle(yaml configYAMLs: String, gradle expectedGradle: String, line: UInt = #line) throws {
        //if expectedGradle.isEmpty { return }
        print("CHECKING YAML:", configYAMLs, separator: "\n")
        let yamls = try YAML.parse(yamls: configYAMLs)
        guard var config = try yamls.first?.json() else {
            return XCTFail("no YAML in arg")
        }
        for yaml in yamls.dropFirst() {
            try config.merge(with: yaml.json())
        }

        print("AS JSON:", try config.prettyJSON, separator: "\n")
        let holder = try config.decode() as GradleHolder
        let gradle = holder.gradle.formatted()
        print("AGAINST GRADLE:", gradle, separator: "\n")
        XCTAssertEqual(expectedGradle.trimmingCharacters(in: .whitespacesAndNewlines), gradle.trimmingCharacters(in: .whitespacesAndNewlines), line: line)
    }

    /// build up the sample from: https://github.com/gradle/native-samples/blob/master/build.gradle.kts
    func testSimplePluginGradle() throws {
        try expectGradle(yaml: """
        gradle:
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
        gradle:
          contents:
            - block: 'plugins'
              contents:
                - 'id("org.gradle.samples.plugin1")'
        ---
        gradle:
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
        gradle:
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
        gradle:
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
        gradle:
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
        gradle:
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
}

/// A `skip.yml` file, containing configuration information for a Skip project.
struct SkipConfig : Equatable, Codable {
    var module: String?
    var package: String?
    var process: [Process]? = nil

    struct Process : Equatable, Codable {
        var x: String?
    }
}

///// A Gradle project, represented by a `build.gradle.kts` file.
/////
///// https://docs.gradle.org/current/dsl/org.gradle.api.Project.html#N14DC0
//struct GradleProject : Equatable, Codable {
//
//}

struct GradleHolder : Equatable, Codable {
    let gradle: GradleConfig
}

struct GradleContext {
}

typealias BlockOrCommand = Either<String>.Or<GradleBlock>

func format(commandBlock: BlockOrCommand, context: GradleContext, indent: Int) -> String {
    func formatCommand(_ command: String) -> String {
        String(repeating: " ", count: indent) + command + "\n"
    }

    func formatBlock(_ block: GradleBlock) -> String {
        var str = ""
        str += String(repeating: " ", count: indent)
        str += block.block
        if let params = block.param?.map({ [$0 ]}, { $0 }).value {
            str += "(" + params.joined(separator: ", ") + ")"
        }
        str += " {\n"
        str += block.formatted(context: context, indent: indent)
        str += String(repeating: " ", count: indent) + "}\n"
        return str
    }

    return commandBlock.map(formatCommand, formatBlock).value
}

func format(blocks: [BlockOrCommand]?, context: GradleContext, indent: Int) -> String {
    guard let blocks else { return "" }

    var content = ""
    var lastWasBlock = false
    // blocks with the same name are merged together; this allow us to use simple JSON merging
    var mergedBlocks: [(id: String?, boc: BlockOrCommand)] = []

    for boc in blocks {
        if let block = boc.infer() as GradleBlock? {
            // if a block with the same name ("block" field) exists, then update that block; otherwise, append it
            if let index = mergedBlocks.firstIndex(where: { $0.0 == block.block }) {
                if var fromBlock = mergedBlocks[index].boc.infer() as GradleBlock? {
                    fromBlock.contents = (fromBlock.contents ?? []) + (block.contents ?? [])
                    mergedBlocks[index].boc = .init(fromBlock)
                }
            } else {
                mergedBlocks.append((id: block.block, boc: .init(block)))
            }
        } else {
            // command or something other than a block
            mergedBlocks.append((id: nil, boc: boc))
        }
    }
    for (index, (_, block)) in mergedBlocks.enumerated() {
        if index > 0 {
            if lastWasBlock && indent == 0 {
                // extra space after blocks, only when at top level
                content += "\n"
            }
        }
        content += format(commandBlock: block, context: context, indent: indent)
        lastWasBlock = (block.infer() as GradleBlock?) != nil
    }
    return content
}

struct GradleConfig : Equatable, Codable {
    var name: String?
    var contents: [BlockOrCommand]?

    func formatted(context: GradleContext = GradleContext()) -> String {
        var content = ""
        content += format(blocks: contents, context: context, indent: 0)
        return content
    }
}

struct GradleBlock : Equatable, Codable {
    var block: String
    var param: Either<String>.Or<[String]>?
    var contents: [BlockOrCommand]?
    var enabled: Bool?

    func formatted(context: GradleContext, indent: Int) -> String {
        if enabled == false {
            return ""
        }
        var content = ""
        content += format(blocks: contents, context: context, indent: indent + 4)
        return content
    }
}



// TODO: Move into Universal

extension JSON {
    /// Merges the other JSON into this JSON
    ///
    /// Array types are concatenated and object key are replaced/added from the other JSON.
    /// All other types are replaced directly.
    public mutating func merge(with other: JSON) throws {
        try self.merge(with: other, typecheck: true)
    }

    /// Returns a JSON consisting of this JSON merged with the other JSON.
    ///
    /// Array types are concatenated and object key are replaced/added from the other JSON.
    /// All other types are replaced directly.
    public func merged(with other: JSON) throws -> JSON {
        var merged = self
        try merged.merge(with: other, typecheck: true)
        return merged
    }

    @usableFromInline mutating func merge(with otherJSON: JSON, typecheck: Bool) throws {
        if let oobj = otherJSON.object {
            if var sobj = self.object {
                for (okey, ovalue) in oobj {
                    sobj[okey] = try sobj[okey]?.merged(with: ovalue) ?? ovalue
                }
                self = .object(sobj)
            } else {
                self = otherJSON
            }
        } else if let oarr = otherJSON.array {
            if let sarr = self.array {
                self = .array(sarr + oarr)
            } else {
                self = otherJSON
            }
        } else {
            // simple value replacement
            self = otherJSON
        }
    }
}
