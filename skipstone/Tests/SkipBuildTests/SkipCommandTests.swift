// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

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

    // disabled because on CI, the doctor command doesn't locate the `skip` tool itself
    func XXXtestDoctorCommand() async throws {
        // run skip doctor with JSON array output and make sure we can parse the result
        try await XCTAssertEqualAsync(["msg": "Skip Doctor"], skipstone(["doctor", "-jA"]).json().array?.first)
    }

    func testLibInitZeroCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "zero-project", zero: true, mode: [.transpiledModel], moduleNames: "SomeModule")
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
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "zero-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "SomeModuleTests", dependencies: [
                    "SomeModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        // Setting the SKIP_ZERO=1 environment will strip out the Skip plugin and all Skip dependencies
        if Context.environment["SKIP_ZERO"] ?? "0" != "0" {
            package.targets.forEach { target in
                // remove the Skip plugin
                target.plugins?.removeAll(where: {
                    if case .plugin(let name, _) = $0 {
                        return name == "skipstone"
                    } else {
                        return false
                    }
                })

                // remove the Skip target dependencies
                target.dependencies.removeAll(where: { dependency in
                    if case .productItem(_, let package, _, _) = dependency {
                        return package == "skip" || package?.hasPrefix("skip-") == true
                    } else {
                        return false
                    }
                })
            }

            // remove the Skip package dependencies
            package.dependencies.removeAll(where: { dependency in
                if case .sourceControl(_, let url, _) = dependency.kind {
                    return url.hasPrefix("https://source.skip.dev/") || url.hasPrefix("https://source.skip.tools/")
                } else {
                    return false
                }
            })
        }

        """)
    }

    func testLibInitNoTestCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "tiny-project", zero: false, mode: [.transpiledModel], tests: false, moduleNames: "TeenyModule")
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
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "tiny-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "TeenyModule", type: .dynamic, targets: ["TeenyModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "TeenyModule", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitNoZeroCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "basic-project", zero: false, mode: [.transpiledModel], moduleNames: "SomeModule")
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

        let moduleCode = try load("Sources/SomeModule/SomeModule.swift")
        XCTAssertEqual(moduleCode, """
        import Foundation

        public class SomeModuleModule {
        }

        """)

        let testCaseCode = try load("Tests/SomeModuleTests/SomeModuleTests.swift")
        XCTAssertEqual(testCaseCode, """
        import XCTest
        import OSLog
        import Foundation
        @testable import SomeModule

        let logger: Logger = Logger(subsystem: "SomeModule", category: "Tests")

        @available(macOS 13, *)
        final class SomeModuleTests: XCTestCase {

            func testSomeModule() throws {
                logger.log("running testSomeModule")
                XCTAssertEqual(1 + 2, 3, "basic test")
            }

            func testDecodeType() throws {
                // load the TestData.json file from the Resources folder and decode it into a struct
                let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
                let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
                XCTAssertEqual("SomeModule", testData.testModuleName)
            }

        }

        struct TestData : Codable, Hashable {
            var testModuleName: String
        }

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "basic-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "SomeModuleTests", dependencies: [
                    "SomeModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitFreeCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "free-project", free: true, zero: false, mode: [.transpiledModel], tests: true, moduleNames: "FreeModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ LICENSE.txt
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
        XCTAssertTrue(XCSkipTests.hasPrefix(SourceLicense.lgpl3LinkingException.sourceHeader), "bad source license in: \(XCSkipTests)")

        let FreeModuleTests = try load("Tests/FreeModuleTests/FreeModuleTests.swift")
        XCTAssertTrue(FreeModuleTests.hasPrefix(SourceLicense.lgpl3LinkingException.sourceHeader), "bad source license in: \(FreeModuleTests)")

        let FreeModule = try load("Sources/FreeModule/FreeModule.swift")
        XCTAssertTrue(FreeModule.hasPrefix(SourceLicense.lgpl3LinkingException.sourceHeader), "bad source license in: \(FreeModule)")

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "free-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "FreeModule", type: .dynamic, targets: ["FreeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "FreeModule", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "FreeModuleTests", dependencies: [
                    "FreeModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitBridgedCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "free-project", zero: false, bridged: true, mode: [.transpiledModel], tests: true, moduleNames: "BridgedModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ BridgedModule
        │     ├─ BridgedModule.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           └─ BridgedModuleTests
              ├─ BridgedModuleTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

        let XCSkipTests = try load("Tests/BridgedModuleTests/XCSkipTests.swift")
        XCTAssertTrue(XCSkipTests.contains("testSkipModule()"))

        //let BridgedModuleTests = try load("Tests/BridgedModuleTests/BridgedModuleTests.swift")

        let BridgedModule = try load("Sources/BridgedModule/BridgedModule.swift")
        XCTAssertEqual(BridgedModule, """
        #if !SKIP_BRIDGE
        import Foundation

        public class BridgedModuleModule {
        }

        #endif

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "free-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "BridgedModule", type: .dynamic, targets: ["BridgedModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "BridgedModule", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "BridgedModuleTests", dependencies: [
                    "BridgedModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
            package.dependencies += [.package(url: "https://source.skip.tools/skip-bridge.git", "0.0.0"..<"2.0.0")]
            package.targets.forEach({ target in
                target.dependencies += [.product(name: "SkipBridge", package: "skip-bridge")]
            })
            // all library types must be dynamic to support bridging
            package.products = package.products.map({ product in
                guard let libraryProduct = product as? Product.Library else { return product }
                return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
            })
        }

        """)
    }

    func testLibInitAppDefaults() async throws {
        let projectName = "cool-app"
        let moduleName = "APPNAME"
        let appid = "some.cool.app"
        let (_, projectTree) = try await skipInit(projectName: projectName, free: true, mode: [.transpiledApp], fastlane: false, appid: appid, moduleNames: moduleName)
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ APPNAME.xcconfig
        │  ├─ APPNAME.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ APPNAME App.xcscheme
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ Main.swift
        ├─ LICENSE.txt
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ APPNAME
        │     ├─ APPNAMEApp.swift
        │     ├─ ContentView.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           └─ APPNAMETests
              ├─ APPNAMETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

    }

    func testLibInitAppFastlane() async throws {
        let projectName = "cool-app"
        let moduleName = "APPNAME"
        let appid = "some.cool.app"
        let (_, projectTree) = try await skipInit(projectName: projectName, free: true, mode: [.transpiledApp], fastlane: true, appid: appid, moduleNames: moduleName)
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ fastlane
        │  │  ├─ Appfile
        │  │  ├─ Fastfile
        │  │  ├─ README.md
        │  │  └─ metadata
        │  │     └─ android
        │  │        └─ en-US
        │  │           ├─ full_description.txt
        │  │           ├─ short_description.txt
        │  │           └─ title.txt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ APPNAME.xcconfig
        │  ├─ APPNAME.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ APPNAME App.xcscheme
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  ├─ Sources
        │  │  └─ Main.swift
        │  └─ fastlane
        │     ├─ AppStore.xcconfig
        │     ├─ Appfile
        │     ├─ Deliverfile
        │     ├─ Fastfile
        │     ├─ README.md
        │     └─ metadata
        │        ├─ app_privacy_details.json
        │        ├─ en-US
        │        │  ├─ description.txt
        │        │  ├─ keywords.txt
        │        │  ├─ privacy_url.txt
        │        │  ├─ release_notes.txt
        │        │  ├─ software_url.txt
        │        │  ├─ subtitle.txt
        │        │  ├─ support_url.txt
        │        │  ├─ title.txt
        │        │  └─ version_whats_new.txt
        │        └─ rating.json
        ├─ LICENSE.txt
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ APPNAME
        │     ├─ APPNAMEApp.swift
        │     ├─ ContentView.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           └─ APPNAMETests
              ├─ APPNAMETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

    }

    func testLibInitAppIconCommand() async throws {
        let projectName = "cool-app"
        let moduleName = "APPNAME"
        let appid = "some.cool.app"
        let (projectURL, projectTree) = try await skipInit(projectName: projectName, free: true, mode: [.transpiledApp], fastlane: false, appid: appid, backgroundColor: "4994EC", moduleNames: moduleName)
        #if os(macOS) // icons are not generated on Linux
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        ├─ kotlin
        │  │        │  └─ Main.kt
        │  │        └─ res
        │  │           ├─ mipmap-anydpi
        │  │           │  └─ ic_launcher.xml
        │  │           ├─ mipmap-hdpi
        │  │           │  ├─ ic_launcher.png
        │  │           │  ├─ ic_launcher_background.png
        │  │           │  ├─ ic_launcher_foreground.png
        │  │           │  └─ ic_launcher_monochrome.png
        │  │           ├─ mipmap-mdpi
        │  │           │  ├─ ic_launcher.png
        │  │           │  ├─ ic_launcher_background.png
        │  │           │  ├─ ic_launcher_foreground.png
        │  │           │  └─ ic_launcher_monochrome.png
        │  │           ├─ mipmap-xhdpi
        │  │           │  ├─ ic_launcher.png
        │  │           │  ├─ ic_launcher_background.png
        │  │           │  ├─ ic_launcher_foreground.png
        │  │           │  └─ ic_launcher_monochrome.png
        │  │           ├─ mipmap-xxhdpi
        │  │           │  ├─ ic_launcher.png
        │  │           │  ├─ ic_launcher_background.png
        │  │           │  ├─ ic_launcher_foreground.png
        │  │           │  └─ ic_launcher_monochrome.png
        │  │           └─ mipmap-xxxhdpi
        │  │              ├─ ic_launcher.png
        │  │              ├─ ic_launcher_background.png
        │  │              ├─ ic_launcher_foreground.png
        │  │              └─ ic_launcher_monochrome.png
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ APPNAME.xcconfig
        │  ├─ APPNAME.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ APPNAME App.xcscheme
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  ├─ AppIcon-20@2x.png
        │  │  │  ├─ AppIcon-20@2x~ipad.png
        │  │  │  ├─ AppIcon-20@3x.png
        │  │  │  ├─ AppIcon-20~ipad.png
        │  │  │  ├─ AppIcon-29.png
        │  │  │  ├─ AppIcon-29@2x.png
        │  │  │  ├─ AppIcon-29@2x~ipad.png
        │  │  │  ├─ AppIcon-29@3x.png
        │  │  │  ├─ AppIcon-29~ipad.png
        │  │  │  ├─ AppIcon-40@2x.png
        │  │  │  ├─ AppIcon-40@2x~ipad.png
        │  │  │  ├─ AppIcon-40@3x.png
        │  │  │  ├─ AppIcon-40~ipad.png
        │  │  │  ├─ AppIcon-83.5@2x~ipad.png
        │  │  │  ├─ AppIcon@2x.png
        │  │  │  ├─ AppIcon@2x~ipad.png
        │  │  │  ├─ AppIcon@3x.png
        │  │  │  ├─ AppIcon~ios-marketing.png
        │  │  │  ├─ AppIcon~ipad.png
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ Main.swift
        ├─ LICENSE.txt
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ APPNAME
        │     ├─ APPNAMEApp.swift
        │     ├─ ContentView.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           └─ APPNAMETests
              ├─ APPNAMETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let _ = projectURL

//        #warning("TODO: debugging")
//        print("""
//        gradle.withenv -p \(projectURL.path)/Android --console=plain launchDebug &&
//            xcodebuild -project \(projectURL.path)/Darwin/*.xcodeproj -derivedDataPath .build/Darwin/DerivedData -skipPackagePluginValidation -scheme \(moduleName)App -destination \"generic/platform=iOS Simulator\" build CODE_SIGNING_ALLOWED=NO ZERO_AR_DATE=1 SKIP_BUILD_APK=NO SKIP_LAUNCH_APK=NO &&
//            xcrun simctl install booted ".build/Darwin/DerivedData/Build/Products/Debug-iphonesimulator/\(moduleName)App.app" &&
//            xcrun simctl launch booted "\(appid)"
//        """)
//
//        try await Process.checkNonZeroExit(args: "open", "\(projectURL.path)/Darwin/\(moduleName).xcodeproj")

        #endif
    }

    func testLibInitNativeModelCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "basic-project", mode: [.nativeModel], tests: true, moduleNames: "SomeModule")
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

        let moduleCode = try load("Sources/SomeModule/SomeModule.swift")
        XCTAssertEqual(moduleCode, """
        import Foundation

        public class SomeModuleModule {

            public static func createSomeModuleType(id: UUID, delay: Double? = nil) async throws -> SomeModuleType {
                if let delay = delay {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                return SomeModuleType(id: id)
            }

            /// An example of a type that can be bridged between Swift and Kotlin
            public struct SomeModuleType: Identifiable, Hashable, Codable {
                public var id: UUID
            }
        }

        """)

        let testCaseCode = try load("Tests/SomeModuleTests/SomeModuleTests.swift")
        XCTAssertEqual(testCaseCode, """
        import XCTest
        import OSLog
        import Foundation
        import SkipBridge
        @testable import SomeModule

        let logger: Logger = Logger(subsystem: "SomeModule", category: "Tests")

        @available(macOS 13, *)
        final class SomeModuleTests: XCTestCase {
            override func setUp() {
                #if os(Android)
                // needed to load the compiled bridge from the transpiled tests
                loadPeerLibrary(packageName: "basic-project", moduleName: "SomeModule")
                #endif
            }

            func testSomeModule() throws {
                logger.log("running testSomeModule")
                XCTAssertEqual(1 + 2, 3, "basic test")
            }

            func testAsyncThrowsFunction() async throws {
                let id = UUID()
                let type: SomeModuleModule.SomeModuleType = try await SomeModuleModule.createSomeModuleType(id: id, delay: 0.001)
                XCTAssertEqual(id, type.id)
            }

        }

        """)

        let SkipYML = try load("Sources/SomeModule/Skip/skip.yml")
        XCTAssertEqual(SkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled Skip Fuse module
        skip:
          mode: 'native'
          bridging: true

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "basic-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: [
                    .product(name: "SkipFuse", package: "skip-fuse")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "SomeModuleTests", dependencies: [
                    "SomeModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitKotlincompatCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "basic-project", mode: [.nativeModel], kotlincompat: true, moduleNames: "SomeModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        └─ Sources
           └─ SomeModule
              ├─ Resources
              │  └─ Localizable.xcstrings
              ├─ Skip
              │  └─ skip.yml
              └─ SomeModule.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

        let moduleCode = try load("Sources/SomeModule/SomeModule.swift")
        XCTAssertEqual(moduleCode, """
        import Foundation

        public class SomeModuleModule {

            public static func createSomeModuleType(id: UUID, delay: Double? = nil) async throws -> SomeModuleType {
                if let delay = delay {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                return SomeModuleType(id: id)
            }

            /// An example of a type that can be bridged between Swift and Kotlin
            public struct SomeModuleType: Identifiable, Hashable, Codable {
                public var id: UUID
            }
        }

        """)

        let SkipYML = try load("Sources/SomeModule/Skip/skip.yml")
        XCTAssertEqual(SkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled Skip Fuse module
        skip:
          mode: 'native'
          bridging:
            enabled: true
            options: 'kotlincompat'

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "basic-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: [
                    .product(name: "SkipFuse", package: "skip-fuse")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    /// A multi-module native app with transpiled app and compiled model
    func testLibInitAppNativeModelCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "cool-app", zero: false, mode: [.nativeModel], tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "AppModule", "ModelModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ AppModule.xcconfig
        │  ├─ AppModule.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ AppModule App.xcscheme
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ Main.swift
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ AppModule
        │  │  ├─ AppModuleApp.swift
        │  │  ├─ ContentView.swift
        │  │  ├─ Resources
        │  │  │  ├─ Localizable.xcstrings
        │  │  │  └─ Module.xcassets
        │  │  │     └─ Contents.json
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ ModelModule
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           ├─ AppModuleTests
           │  ├─ AppModuleTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ ModelModuleTests
              ├─ ModelModuleTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))

        let AppSkipYML = try load("Sources/AppModule/Skip/skip.yml")
        XCTAssertEqual(AppSkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a transpiled Skip Lite module
        skip:
          mode: 'transpiled'

        """)

        let ModelSkipYML = try load("Sources/ModelModule/Skip/skip.yml")
        XCTAssertEqual(ModelSkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled Skip Fuse module
        skip:
          mode: 'native'
          bridging: true

        """)

        let testCaseCode = try load("Tests/ModelModuleTests/ModelModuleTests.swift")
        XCTAssertEqual(testCaseCode, """
        import XCTest
        import OSLog
        import Foundation
        import SkipBridge
        @testable import ModelModule

        let logger: Logger = Logger(subsystem: "ModelModule", category: "Tests")

        @available(macOS 13, *)
        final class ModelModuleTests: XCTestCase {
            override func setUp() {
                #if os(Android)
                // needed to load the compiled bridge from the transpiled tests
                loadPeerLibrary(packageName: "cool-app", moduleName: "ModelModule")
                #endif
            }

            func testModelModule() throws {
                logger.log("running testModelModule")
                XCTAssertEqual(1 + 2, 3, "basic test")
            }

            func testViewModel() async throws {
                let vm = ViewModel()
                vm.items.append(Item(title: "ABC"))
                XCTAssertFalse(vm.items.isEmpty)
                XCTAssertEqual("ABC", vm.items.last?.title)

                vm.clear()
                XCTAssertTrue(vm.items.isEmpty)
            }

        }

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "AppModule", type: .dynamic, targets: ["AppModule"]),
                .library(name: "ModelModule", type: .dynamic, targets: ["ModelModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "AppModule", dependencies: [
                    "ModelModule",
                    .product(name: "SkipUI", package: "skip-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "AppModuleTests", dependencies: [
                    "AppModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "ModelModule", dependencies: [
                    .product(name: "SkipFuse", package: "skip-fuse"),
                    .product(name: "SkipModel", package: "skip-model")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "ModelModuleTests", dependencies: [
                    "ModelModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    /// A multi-module native app
    func testLibInitAppNativeAppModelCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "cool-app", zero: false, mode: [.nativeApp], tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "AppModule", "ModelModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ AppModule.xcconfig
        │  ├─ AppModule.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ AppModule App.xcscheme
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ Main.swift
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ AppModule
        │  │  ├─ AppModuleApp.swift
        │  │  ├─ ContentView.swift
        │  │  ├─ Resources
        │  │  │  ├─ Localizable.xcstrings
        │  │  │  └─ Module.xcassets
        │  │  │     └─ Contents.json
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ ModelModule
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           └─ ModelModuleTests
              ├─ ModelModuleTests.swift
              ├─ Resources
              │  └─ TestData.json
              └─ Skip
                 └─ skip.yml

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))

        let AppSkipYML = try load("Sources/AppModule/Skip/skip.yml")
        XCTAssertEqual(AppSkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled Skip Fuse module
        skip:
          mode: 'native'

        """)

        let SkipYML = try load("Sources/ModelModule/Skip/skip.yml")
        XCTAssertEqual(SkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled Skip Fuse module
        skip:
          mode: 'native'

        """)

        let testCaseCode = try load("Tests/ModelModuleTests/ModelModuleTests.swift")
        XCTAssertEqual(testCaseCode, """
        import XCTest
        import OSLog
        import Foundation
        import SkipBridge
        @testable import ModelModule

        let logger: Logger = Logger(subsystem: "ModelModule", category: "Tests")

        @available(macOS 13, *)
        final class ModelModuleTests: XCTestCase {
            override func setUp() {
                #if os(Android)
                // needed to load the compiled bridge from the transpiled tests
                loadPeerLibrary(packageName: "cool-app", moduleName: "ModelModule")
                #endif
            }

            func testModelModule() throws {
                logger.log("running testModelModule")
                XCTAssertEqual(1 + 2, 3, "basic test")
            }

            func testViewModel() async throws {
                let vm = ViewModel()
                vm.items.append(Item(title: "ABC"))
                XCTAssertFalse(vm.items.isEmpty)
                XCTAssertEqual("ABC", vm.items.last?.title)

                vm.clear()
                XCTAssertTrue(vm.items.isEmpty)
            }

        }

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "AppModule", type: .dynamic, targets: ["AppModule"]),
                .library(name: "ModelModule", type: .dynamic, targets: ["ModelModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "AppModule", dependencies: [
                    "ModelModule",
                    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "ModelModule", dependencies: [
                    .product(name: "SkipFuse", package: "skip-fuse"),
                    .product(name: "SkipModel", package: "skip-model")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "ModelModuleTests", dependencies: [
                    "ModelModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    /// A single-module native app
    func testLibInitAppNativeAppCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "cool-app", zero: false, mode: [.nativeApp], tests: nil, fastlane: false, appid: "some.cool.app", swiftPackageVersion: "6.2", moduleNames: "AppModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ AppModule.xcconfig
        │  ├─ AppModule.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ AppModule App.xcscheme
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ Main.swift
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        └─ Sources
           └─ AppModule
              ├─ AppModuleApp.swift
              ├─ ContentView.swift
              ├─ Resources
              │  ├─ Localizable.xcstrings
              │  └─ Module.xcassets
              │     └─ Contents.json
              ├─ Skip
              │  └─ skip.yml
              └─ ViewModel.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))

        let SkipYML = try load("Sources/AppModule/Skip/skip.yml")
        XCTAssertEqual(SkipYML, """
        # Configuration file for Skip (https://skip.dev) project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled Skip Fuse module
        skip:
          mode: 'native'

        """)

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.2
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "AppModule", type: .dynamic, targets: ["AppModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "AppModule", dependencies: [
                    .product(name: "SkipFuseUI", package: "skip-fuse-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitAppFair() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "Free-App", free: false, appfair: true, mode: [.transpiledApp], moduleNames: "FreeApp", "FreeAppModel") // appfair should override free
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ fastlane
        │  │  ├─ Appfile
        │  │  ├─ Fastfile
        │  │  ├─ README.md
        │  │  └─ metadata
        │  │     └─ android
        │  │        └─ en-US
        │  │           ├─ full_description.txt
        │  │           ├─ short_description.txt
        │  │           └─ title.txt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ FreeApp.xcconfig
        │  ├─ FreeApp.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ FreeApp App.xcscheme
        │  ├─ Info.plist
        │  ├─ Sources
        │  │  └─ Main.swift
        │  └─ fastlane
        │     ├─ AppStore.xcconfig
        │     ├─ Appfile
        │     ├─ Deliverfile
        │     ├─ Fastfile
        │     ├─ README.md
        │     └─ metadata
        │        ├─ app_privacy_details.json
        │        ├─ en-US
        │        │  ├─ description.txt
        │        │  ├─ keywords.txt
        │        │  ├─ privacy_url.txt
        │        │  ├─ release_notes.txt
        │        │  ├─ software_url.txt
        │        │  ├─ subtitle.txt
        │        │  ├─ support_url.txt
        │        │  ├─ title.txt
        │        │  └─ version_whats_new.txt
        │        └─ rating.json
        ├─ LICENSE.txt
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ FreeApp
        │  │  ├─ ContentView.swift
        │  │  ├─ FreeAppApp.swift
        │  │  ├─ Resources
        │  │  │  ├─ Localizable.xcstrings
        │  │  │  └─ Module.xcassets
        │  │  │     └─ Contents.json
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ FreeAppModel
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           ├─ FreeAppModelTests
           │  ├─ FreeAppModelTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ FreeAppTests
              ├─ FreeAppTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }

        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "free-app-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "FreeApp", type: .dynamic, targets: ["FreeApp"]),
                .library(name: "FreeAppModel", type: .dynamic, targets: ["FreeAppModel"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://github.com/appfair/appfair-app.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "FreeApp", dependencies: [
                    "FreeAppModel",
                    .product(name: "AppFairUI", package: "appfair-app")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "FreeAppTests", dependencies: [
                    "FreeApp",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "FreeAppModel", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation"),
                    .product(name: "SkipModel", package: "skip-model")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "FreeAppModelTests", dependencies: [
                    "FreeAppModel",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)

        //let fastlaneSoftwareUrliOS = try load("Darwin/fastlane/metadata/en-US/software_url.txt")
        //XCTAssertEqual(fastlaneSoftwareUrliOS, "https://github.com/\(projectName)/\(projectName)")

        //let fastlaneSupportUrliOS = try load("Darwin/fastlane/metadata/en-US/support_url.txt")
        //XCTAssertEqual(fastlaneSupportUrliOS, "https://github.com/\(projectName)/\(projectName)/issues")
    }

    func testLibInitApp3ModuleCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "cool-app", zero: true, mode: [.transpiledModel], tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "TopModule", "MiddleModule", "BottomModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  ├─ Sources
        │  │  └─ Main.swift
        │  ├─ TopModule.xcconfig
        │  └─ TopModule.xcodeproj
        │     ├─ project.pbxproj
        │     └─ xcshareddata
        │        └─ xcschemes
        │           └─ TopModule App.xcscheme
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ BottomModule
        │  │  ├─ BottomModule.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ MiddleModule
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  ├─ Skip
        │  │  │  └─ skip.yml
        │  │  └─ ViewModel.swift
        │  └─ TopModule
        │     ├─ ContentView.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ TopModuleApp.swift
        └─ Tests
           ├─ BottomModuleTests
           │  ├─ BottomModuleTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ MiddleModuleTests
           │  ├─ MiddleModuleTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ TopModuleTests
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              ├─ TopModuleTests.swift
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))
        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "TopModule", type: .dynamic, targets: ["TopModule"]),
                .library(name: "MiddleModule", type: .dynamic, targets: ["MiddleModule"]),
                .library(name: "BottomModule", type: .dynamic, targets: ["BottomModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "TopModule", dependencies: [
                    "MiddleModule",
                    .product(name: "SkipUI", package: "skip-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "TopModuleTests", dependencies: [
                    "TopModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "MiddleModule", dependencies: [
                    "BottomModule",
                    .product(name: "SkipModel", package: "skip-model")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "MiddleModuleTests", dependencies: [
                    "MiddleModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "BottomModule", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "BottomModuleTests", dependencies: [
                    "BottomModule",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        // Setting the SKIP_ZERO=1 environment will strip out the Skip plugin and all Skip dependencies
        if Context.environment["SKIP_ZERO"] ?? "0" != "0" {
            package.targets.forEach { target in
                // remove the Skip plugin
                target.plugins?.removeAll(where: {
                    if case .plugin(let name, _) = $0 {
                        return name == "skipstone"
                    } else {
                        return false
                    }
                })

                // remove the Skip target dependencies
                target.dependencies.removeAll(where: { dependency in
                    if case .productItem(_, let package, _, _) = dependency {
                        return package == "skip" || package?.hasPrefix("skip-") == true
                    } else {
                        return false
                    }
                })
            }

            // remove the Skip package dependencies
            package.dependencies.removeAll(where: { dependency in
                if case .sourceControl(_, let url, _) = dependency.kind {
                    return url.hasPrefix("https://source.skip.dev/") || url.hasPrefix("https://source.skip.tools/")
                } else {
                    return false
                }
            })
        }

        """)
    }

    func testLibInitApp5ModuleNoZeroCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "cool-app", zero: false, mode: [.transpiledApp], tests: false, fastlane: false, appid: "some.cool.app", moduleNames: "M1", "M2", "M3", "M4", "M5")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  ├─ M1.xcconfig
        │  ├─ M1.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ M1 App.xcscheme
        │  └─ Sources
        │     └─ Main.swift
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        └─ Sources
           ├─ M1
           │  ├─ ContentView.swift
           │  ├─ M1App.swift
           │  ├─ Resources
           │  │  ├─ Localizable.xcstrings
           │  │  └─ Module.xcassets
           │  │     └─ Contents.json
           │  └─ Skip
           │     └─ skip.yml
           ├─ M2
           │  ├─ Resources
           │  │  └─ Localizable.xcstrings
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ ViewModel.swift
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
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))
        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "M1", type: .dynamic, targets: ["M1"]),
                .library(name: "M2", type: .dynamic, targets: ["M2"]),
                .library(name: "M3", type: .dynamic, targets: ["M3"]),
                .library(name: "M4", type: .dynamic, targets: ["M4"]),
                .library(name: "M5", type: .dynamic, targets: ["M5"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "M1", dependencies: [
                    "M2",
                    .product(name: "SkipUI", package: "skip-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M2", dependencies: [
                    "M3",
                    .product(name: "SkipModel", package: "skip-model")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M3", dependencies: [
                    "M4"
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M4", dependencies: [
                    "M5"
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M5", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitApp5NativeModuleCommand() async throws {
        let (projectURL, projectTree) = try await skipInit(projectName: "cool-app", zero: false, mode: [.nativeModel], tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "M1", "M2", "M3", "M4", "M5")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Android
        │  ├─ app
        │  │  ├─ build.gradle.kts
        │  │  ├─ proguard-rules.pro
        │  │  └─ src
        │  │     └─ main
        │  │        ├─ AndroidManifest.xml
        │  │        └─ kotlin
        │  │           └─ Main.kt
        │  ├─ gradle
        │  │  └─ wrapper
        │  │     └─ gradle-wrapper.properties
        │  ├─ gradle.properties
        │  └─ settings.gradle.kts
        ├─ Darwin
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  ├─ M1.xcconfig
        │  ├─ M1.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ M1 App.xcscheme
        │  └─ Sources
        │     └─ Main.swift
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ M1
        │  │  ├─ ContentView.swift
        │  │  ├─ M1App.swift
        │  │  ├─ Resources
        │  │  │  ├─ Localizable.xcstrings
        │  │  │  └─ Module.xcassets
        │  │  │     └─ Contents.json
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ M2
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  ├─ Skip
        │  │  │  └─ skip.yml
        │  │  └─ ViewModel.swift
        │  ├─ M3
        │  │  ├─ M3.swift
        │  │  └─ Resources
        │  │     └─ Localizable.xcstrings
        │  ├─ M4
        │  │  ├─ M4.swift
        │  │  └─ Resources
        │  │     └─ Localizable.xcstrings
        │  └─ M5
        │     ├─ M5.swift
        │     └─ Resources
        │        └─ Localizable.xcstrings
        └─ Tests
           ├─ M1Tests
           │  ├─ M1Tests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ M2Tests
              ├─ M2Tests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))
        let PackageSwift = try load("Package.swift")
        XCTAssertEqual(PackageSwift, """
        // swift-tools-version: 6.1
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        let package = Package(
            name: "cool-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14)],
            products: [
                .library(name: "M1", type: .dynamic, targets: ["M1"]),
                .library(name: "M2", type: .dynamic, targets: ["M2"]),
                .library(name: "M3", type: .dynamic, targets: ["M3"]),
                .library(name: "M4", type: .dynamic, targets: ["M4"]),
                .library(name: "M5", type: .dynamic, targets: ["M5"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "M1", dependencies: [
                    "M2",
                    .product(name: "SkipUI", package: "skip-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "M1Tests", dependencies: [
                    "M1",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M2", dependencies: [
                    "M3",
                    .product(name: "SkipModel", package: "skip-model"),
                    .product(name: "SkipFuse", package: "skip-fuse")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "M2Tests", dependencies: [
                    "M2",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M3", dependencies: [
                    "M4"
                ], resources: [.process("Resources")]),
                .target(name: "M4", dependencies: [
                    "M5"
                ], resources: [.process("Resources")]),
                .target(name: "M5", dependencies: [], resources: [.process("Resources")]),
            ]
        )

        """)
    }

    /// Default arguments for `skip init` tests
    let initTestArgs = ["-jA", "--no-build", "--no-test", "--show-tree"]

    func skipInit(projectName: String, documented: Bool = false, free: Bool? = nil, zero: Bool? = nil, bridged: Bool? = nil, appfair: Bool? = nil, mode: [ProjectMode], kotlincompat: Bool = false, tests moduleTests: Bool? = nil, fastlane: Bool? = nil, validatePackage: Bool? = true, appid: String? = nil, swiftPackageVersion: String? = nil, resourcePath: String? = "Resources", backgroundColor: String? = nil, moduleNames: String...) async throws -> (projectURL: URL, projectTree: String?) {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory() + "/testLibInitCommand/", isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        var cmd = ["init"] + initTestArgs
        if let resourcePath = resourcePath {
            cmd += ["--resource-path", resourcePath]
        }

        if let backgroundColor = backgroundColor {
            cmd += ["--icon-background", backgroundColor]
        } else {
            cmd += ["--no-icon"]
        }

        if zero == true {
            cmd += ["--zero"]
        } else if zero == false {
            cmd += ["--no-zero"]
        }

        if bridged == true {
            cmd += ["--bridged"]
        } else if zero == false {
            cmd += ["--no-bridged"]
        }

        // conventional Skip apps
        if appfair == true {
            cmd += ["--appfair"]
        } else if appfair == false {
            cmd += ["--no-appfair"]
        }

        if mode.contains(.nativeApp) {
            cmd += ["--native-app"]
        }
        if mode.contains(.transpiledApp) {
            cmd += ["--transpiled-app"]
        }

        if mode.contains(.nativeModel) {
            cmd += ["--native-model"]
            if kotlincompat == true {
                cmd += ["--kotlincompat"]
            }
        }
        if mode.contains(.transpiledModel) {
            cmd += ["--transpiled-model"]
        }

        if moduleTests == true {
            cmd += ["--module-tests"]
        } else if moduleTests == false {
            cmd += ["--no-module-tests"]
        }

        if let swiftPackageVersion {
            cmd += ["--swift-package-version", swiftPackageVersion]
        }

        if fastlane == true {
            cmd += ["--fastlane"]
        } else if fastlane == false {
            cmd += ["--no-fastlane"]
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
        cmd += ["-d", tmpDir.appendingPathComponent(projectName, isDirectory: true).path]

        cmd += [projectName]
        cmd += moduleNames

        // TODO: check that the skip init documentation usage section contains the given function
        if documented {
            let docFilter: Set<String> = Set(initTestArgs)
            let docCommand = cmd.filter({ !docFilter.contains($0) }).joined(separator: " ")
            let initDoc = InitCommand.configuration.usage ?? ""
            XCTAssertTrue(initDoc.contains(docCommand), "command \(docCommand) not contained in InitCommand.configuration.usage")
        }

        let created = try await skipstone(cmd).json()
        XCTAssertEqual(created.array?.first, ["msg": .string("Initializing Skip \(appid == nil && appfair != true ? "library" : "application") \(projectName)")])
        // return the tree output, which is in the 2nd-to-last message
       return (projectURL: tmpDir.appendingPathComponent(projectName, isDirectory: true), projectTree: created.array?.dropLast(2).last?["msg"]?.string)
    }
}


/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
