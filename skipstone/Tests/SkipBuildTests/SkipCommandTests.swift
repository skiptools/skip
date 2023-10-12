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
        let (projectURL, projectTree) = try await libInitComand(projectName: "zero-project", zero: true, moduleNames: "SomeModule")
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
            name: "zero-project",
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

    func testLibInitNoTestCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "tiny-project", zero: false, tests: false, moduleNames: "TeenyModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        └─ Sources
           └─ TeenyModule
              ├─ Resources
              │  └─ Localizable.xcstrings
              ├─ Skip
              │  └─ skip.yml
              └─ TeenyModule.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

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
            name: "tiny-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
            products: [
                .library(name: "TeenyModule", type: .dynamic, targets: ["TeenyModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "TeenyModule", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitNoZeroCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "basic-project", zero: false, moduleNames: "SomeModule")
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
            name: "basic-project",
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

    func testLibInitFreeCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "free-project", free: true, zero: false, tests: true, moduleNames: "FreeModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ LICENSE.LGPL
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ FreeModule
        │     ├─ FreeModule.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           └─ FreeModuleTests
              ├─ FreeModuleTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

        let XCSkipTests = try load("Tests/FreeModuleTests/XCSkipTests.swift")
        XCTAssertTrue(XCSkipTests.contains("testSkipModule()"))
        XCTAssertTrue(XCSkipTests.contains("This is free software"))

        let FreeModuleTests = try load("Tests/FreeModuleTests/FreeModuleTests.swift")
        XCTAssertTrue(FreeModuleTests.contains("This is free software"))

        let FreeModule = try load("Sources/FreeModule/FreeModule.swift")
        XCTAssertTrue(FreeModule.contains("This is free software"))

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 5.9
        // This is free software: you can redistribute and/or modify it
        // under the terms of the GNU Lesser General Public License 3.0
        // as published by the Free Software Foundation https://fsf.org
        
        import PackageDescription

        let package = Package(
            name: "free-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
            products: [
                .library(name: "FreeModule", type: .dynamic, targets: ["FreeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "FreeModule", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "FreeModuleTests", dependencies: ["FreeModule", .product(name: "SkipTest", package: "skip")], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitAppCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", appid: "some.cool.app", moduleNames: "APPNAME")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ APPNAME.xcconfig
        ├─ APPNAME.xcodeproj
        │  └─ project.pbxproj
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  ├─ APPNAME
        │  │  ├─ APPNAME.swift
        │  │  ├─ APPNAMEApp.swift
        │  │  ├─ ContentView.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     ├─ AndroidManifest.xml
        │  │     └─ skip.yml
        │  └─ APPNAMEApp
        │     ├─ APPNAMEAppMain.swift
        │     ├─ Assets.xcassets
        │     │  ├─ AccentColor.colorset
        │     │  │  └─ Contents.json
        │     │  ├─ AppIcon.appiconset
        │     │  │  └─ Contents.json
        │     │  └─ Contents.json
        │     └─ Capabilities.entitlements
        └─ Tests
           └─ APPNAMETests
              ├─ APPNAMETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Sources/APPNAME/Skip/AndroidManifest.xml")
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
                .library(name: "APPNAME", type: .dynamic, targets: ["APPNAME"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "APPNAME", dependencies: (zero ? [] : [.product(name: "SkipUI", package: "skip-ui")]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "APPNAMETests", dependencies: ["APPNAME"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
            ]
        )

        """)
    }

    func testLibInitApp3ModuleCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", tests: true, appid: "some.cool.app", moduleNames: "TOP_MODULE", "MIDDLE_MODULE", "BOTTOM_MODULE")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  ├─ BOTTOM_MODULE
        │  │  ├─ BOTTOM_MODULE.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ MIDDLE_MODULE
        │  │  ├─ MIDDLE_MODULE.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ TOP_MODULE
        │  │  ├─ ContentView.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  ├─ Skip
        │  │  │  ├─ AndroidManifest.xml
        │  │  │  └─ skip.yml
        │  │  ├─ TOP_MODULE.swift
        │  │  └─ TOP_MODULEApp.swift
        │  └─ TOP_MODULEApp
        │     ├─ Assets.xcassets
        │     │  ├─ AccentColor.colorset
        │     │  │  └─ Contents.json
        │     │  ├─ AppIcon.appiconset
        │     │  │  └─ Contents.json
        │     │  └─ Contents.json
        │     ├─ Capabilities.entitlements
        │     └─ TOP_MODULEAppMain.swift
        ├─ TOP_MODULE.xcconfig
        ├─ TOP_MODULE.xcodeproj
        │  └─ project.pbxproj
        └─ Tests
           ├─ BOTTOM_MODULETests
           │  ├─ BOTTOM_MODULETests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ MIDDLE_MODULETests
           │  ├─ MIDDLE_MODULETests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ TOP_MODULETests
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              ├─ TOP_MODULETests.swift
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Sources/TOP_MODULE/Skip/AndroidManifest.xml")
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
                .library(name: "TOP_MODULE", type: .dynamic, targets: ["TOP_MODULE"]),
                .library(name: "MIDDLE_MODULE", type: .dynamic, targets: ["MIDDLE_MODULE"]),
                .library(name: "BOTTOM_MODULE", type: .dynamic, targets: ["BOTTOM_MODULE"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "TOP_MODULE", dependencies: ["MIDDLE_MODULE"] + (zero ? [] : [.product(name: "SkipUI", package: "skip-ui")]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "TOP_MODULETests", dependencies: ["TOP_MODULE"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
                .target(name: "MIDDLE_MODULE", dependencies: ["BOTTOM_MODULE"] + (zero ? [] : [.product(name: "SkipModel", package: "skip-model")]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "MIDDLE_MODULETests", dependencies: ["MIDDLE_MODULE"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
                .target(name: "BOTTOM_MODULE", dependencies: (zero ? [] : [.product(name: "SkipFoundation", package: "skip-foundation")]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "BOTTOM_MODULETests", dependencies: ["BOTTOM_MODULE"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
            ]
        )

        """)
    }

    func testLibInitApp5ModuleNoZeroCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", zero: false, tests: false, appid: "some.cool.app", moduleNames: "M1", "M2", "M3", "M4", "M5")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ M1.xcconfig
        ├─ M1.xcodeproj
        │  └─ project.pbxproj
        ├─ Package.swift
        ├─ README.md
        └─ Sources
           ├─ M1
           │  ├─ ContentView.swift
           │  ├─ M1.swift
           │  ├─ M1App.swift
           │  ├─ Resources
           │  │  └─ Localizable.xcstrings
           │  └─ Skip
           │     ├─ AndroidManifest.xml
           │     └─ skip.yml
           ├─ M1App
           │  ├─ Assets.xcassets
           │  │  ├─ AccentColor.colorset
           │  │  │  └─ Contents.json
           │  │  ├─ AppIcon.appiconset
           │  │  │  └─ Contents.json
           │  │  └─ Contents.json
           │  ├─ Capabilities.entitlements
           │  └─ M1AppMain.swift
           ├─ M2
           │  ├─ M2.swift
           │  ├─ Resources
           │  │  └─ Localizable.xcstrings
           │  └─ Skip
           │     └─ skip.yml
           ├─ M3
           │  ├─ M3.swift
           │  ├─ Resources
           │  │  └─ Localizable.xcstrings
           │  └─ Skip
           │     └─ skip.yml
           ├─ M4
           │  ├─ M4.swift
           │  ├─ Resources
           │  │  └─ Localizable.xcstrings
           │  └─ Skip
           │     └─ skip.yml
           └─ M5
              ├─ M5.swift
              ├─ Resources
              │  └─ Localizable.xcstrings
              └─ Skip
                 └─ skip.yml

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Sources/M1/Skip/AndroidManifest.xml")
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

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
            products: [
                .library(name: "M1", type: .dynamic, targets: ["M1"]),
                .library(name: "M2", type: .dynamic, targets: ["M2"]),
                .library(name: "M3", type: .dynamic, targets: ["M3"]),
                .library(name: "M4", type: .dynamic, targets: ["M4"]),
                .library(name: "M5", type: .dynamic, targets: ["M5"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "0.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "0.0.0")
            ],
            targets: [
                .target(name: "M1", dependencies: ["M2", .product(name: "SkipUI", package: "skip-ui")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M2", dependencies: ["M3", .product(name: "SkipModel", package: "skip-model")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M3", dependencies: ["M4"], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M4", dependencies: ["M5"], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M5", dependencies: [.product(name: "SkipFoundation", package: "skip-foundation")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func libInitComand(projectName: String, free: Bool? = nil, zero: Bool? = nil, tests moduleTests: Bool? = nil, validatePackage: Bool? = true, appid: String? = nil, resourcePath: String? = "Resources", moduleNames: String...) async throws -> (projectURL: URL, projectTree: String?) {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory() + "/testLibInitCommand/", isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        var cmd = ["lib", "init", "-jA", "--no-build", "--no-test", "--show-tree"]
        if let resourcePath = resourcePath {
            cmd += ["--resource-path", resourcePath]
        }
        if zero == true {
            cmd += ["--zero"]
        } else if zero == false {
            cmd += ["--no-zero"]
        }

        if moduleTests == true {
            cmd += ["--module-tests"]
        } else if moduleTests == false {
            cmd += ["--no-module-tests"]
        }

        if validatePackage == true {
            cmd += ["--validate-package"]
        } else if moduleTests == false {
            cmd += ["--no-validate-package"]
        }

        if free == true {
            cmd += ["--free"]
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
