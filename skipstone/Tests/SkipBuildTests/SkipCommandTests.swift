import XCTest
@testable import SkipBuild
import TSCBasic

final class SkipCommandTests: XCTestCase {
    func testVersionCommand() async throws {
        try await XCTAssertEqualAsync(skipVersion.json(), skipstone(["version", "-j"]).json()["version"])
    }

    func testInfoCommand() async throws {
        _ = try await skipstone(["info", "-jA"]).json()
    }

    func testDoctorCommand() async throws {
        // run skip doctor with JSON array output and make sure we can parse the result
        try await XCTAssertEqualAsync(["msg": "Skip Doctor"], skipstone(["doctor", "-jA"]).json().array?.first)
    }

    func testLibInitZeroCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "basicProject", zero: true, moduleNames: "SomeModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ SomeModule
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ SomeModule.swift
        └─ Tests
           └─ SomeModuleTests
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              ├─ SomeModuleTests.swift
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

        let XCSkipTests = try load("Tests/SomeModuleTests/XCSkipTests.swift")
        XCTAssertTrue(XCSkipTests.contains("testSkipModule()"))

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 5.9
        // This is a Skip (https://skip.tools) package,
        // containing a Swift Package Manager project
        // that will use the Skip build plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription
        import Foundation

        // Set SKIP_ZERO=1 to build without Skip libraries
        let zero = ProcessInfo.processInfo.environment["SKIP_ZERO"] != nil
        let skipstone = !zero ? [Target.PluginUsage.plugin(name: "skipstone", package: "skip")] : []

        let package = Package(
            name: "basicProject",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: (zero ? [] : [.product(name: "SkipFoundation", package: "skip-foundation")]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "SomeModuleTests", dependencies: ["SomeModule"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
            ]
        )
        """)
    }

    func testLibInitNoZeroCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "basicProject", zero: false, moduleNames: "SomeModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ SomeModule
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ SomeModule.swift
        └─ Tests
           └─ SomeModuleTests
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              ├─ SomeModuleTests.swift
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

        let XCSkipTests = try load("Tests/SomeModuleTests/XCSkipTests.swift")
        XCTAssertTrue(XCSkipTests.contains("testSkipModule()"))

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 5.9
        // This is a Skip (https://skip.tools) package,
        // containing a Swift Package Manager project
        // that will use the Skip build plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription

        let package = Package(
            name: "basicProject",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "SomeModuleTests", dependencies: ["SomeModule", .product(name: "SkipTest", package: "skip")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )
        """)
    }

    func testLibInitAppCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", appid: "some.cool.app", moduleNames: "MODULE_NAME")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ MODULE_NAME.xcconfig
        ├─ MODULE_NAME.xcodeproj
        │  └─ project.pbxproj
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  ├─ MODULE_NAME
        │  │  ├─ ContentView.swift
        │  │  ├─ MODULE_NAME.swift
        │  │  ├─ MODULE_NAMEApp.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     ├─ AndroidManifest.xml
        │  │     └─ skip.yml
        │  └─ MODULE_NAMEApp
        │     ├─ Assets.xcassets
        │     │  ├─ AccentColor.colorset
        │     │  │  └─ Contents.json
        │     │  ├─ AppIcon.appiconset
        │     │  │  └─ Contents.json
        │     │  └─ Contents.json
        │     └─ MODULE_NAMEAppMain.swift
        └─ Tests
           └─ MODULE_NAMETests
              ├─ MODULE_NAMETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Sources/MODULE_NAME/Skip/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))
        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 5.9
        // This is a Skip (https://skip.tools) package,
        // containing a Swift Package Manager project
        // that will use the Skip build plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription
        import Foundation

        // Set SKIP_ZERO=1 to build without Skip libraries
        let zero = ProcessInfo.processInfo.environment["SKIP_ZERO"] != nil
        let skipstone = !zero ? [Target.PluginUsage.plugin(name: "skipstone", package: "skip")] : []

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
            products: [
                .library(name: "MODULE_NAME", type: .dynamic, targets: ["MODULE_NAME"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "MODULE_NAME", dependencies: (zero ? [] : [.product(name: "SkipUI", package: "skip-ui")]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "MODULE_NAMETests", dependencies: ["MODULE_NAME"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
            ]
        )
        """)
    }

    func libInitComand(projectName: String, zero: Bool? = nil, appid: String? = nil, resourcePath: String? = "Resources", moduleNames: String...) async throws -> (projectURL: URL, projectTree: String?) {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory() + "/testLibInitCommand/", isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        var cmd = ["lib", "init", "-jA", "--no-build", "--no-test", "--tree"]
        if let resourcePath = resourcePath {
            cmd += ["--resource-path", resourcePath]
        }
        if zero == true {
            cmd += ["--zero"]
        } else if zero == false {
            cmd += ["--no-zero"]
        }

        if let appid = appid {
            cmd += ["--appid", appid]
        }
        cmd += ["-d", tmpDir.path]

        cmd += [projectName]
        cmd += moduleNames

        let created = try await skipstone(cmd).json()
        XCTAssertEqual(created.array?.first, ["msg": .string("Initializing Skip library \(projectName)")])
        // return the tree output, which is in the 2nd-to-last message
       return (projectURL: tmpDir.appendingPathComponent(projectName, isDirectory: true), projectTree: created.array?.dropLast().last?["msg"]?.string)
    }
}


/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
