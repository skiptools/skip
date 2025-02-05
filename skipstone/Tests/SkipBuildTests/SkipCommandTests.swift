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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: (zero ? [] : [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "SomeModuleTests", dependencies: [
                    "SomeModule"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
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
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
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
        // This is a Skip (https://skip.tools) package,
        // containing a Swift Package Manager project
        // that will use the Skip build plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription

        let package = Package(
            name: "free-project",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
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

    func testLibInitAppDefaults() async throws {
        let projectName = "cool-app"
        let moduleName = "APPNAME"
        let appid = "some.cool.app"
        let (_, projectTree) = try await libInitComand(projectName: projectName, free: true, fastlane: false, appid: appid, moduleNames: moduleName)
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
        │  │  └─ project.pbxproj
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ APPNAMEAppMain.swift
        ├─ LICENSE.GPL
        ├─ Package.swift
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
        let (_, projectTree) = try await libInitComand(projectName: projectName, free: true, fastlane: true, appid: appid, moduleNames: moduleName)
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
        │  │  └─ project.pbxproj
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  ├─ Sources
        │  │  └─ APPNAMEAppMain.swift
        │  └─ fastlane
        │     ├─ AppStore.xcconfig
        │     ├─ Appfile
        │     ├─ Deliverfile
        │     ├─ Fastfile
        │     ├─ README.md
        │     └─ metadata
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
        ├─ LICENSE.GPL
        ├─ Package.swift
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
        let (projectURL, projectTree) = try await libInitComand(projectName: projectName, free: true, fastlane: false, appid: appid, iconColor: "4994EC", moduleNames: moduleName)
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
        │  │  └─ project.pbxproj
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
        │     └─ APPNAMEAppMain.swift
        ├─ LICENSE.GPL
        ├─ Package.swift
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

    func testLibInitNativeCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "basic-project", native: true, moduleNames: "SomeModule")
        XCTAssertEqual(projectTree ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ SomeModule
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ SomeModule.swift
        └─ Tests
           └─ SomeModuleTests
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
        import SkipBridgeKt
        @testable import SomeModule

        let logger: Logger = Logger(subsystem: "SomeModule", category: "Tests")

        @available(macOS 13, *)
        final class SomeModuleTests: XCTestCase {
            override func setUp() {
                #if os(Android)
                // needed to load the compiled bridge from the traspiled tests
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
        # Configuration file for https://skip.tools project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled module
        skip:
          mode: native
          bridging: true
        
        """)

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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "SomeModule", type: .dynamic, targets: ["SomeModule"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", "0.0.0"..<"2.0.0")
            ],
            targets: [
                .target(name: "SomeModule", dependencies: [
                    .product(name: "SkipFuse", package: "skip-fuse")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "SomeModuleTests", dependencies: [
                    "SomeModule",
                    .product(name: "SkipTest", package: "skip")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitAppNativeCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", zero: false, native: true, tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "APP_MODULE", "MODEL_MODULE")
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
        │  ├─ APP_MODULE.xcconfig
        │  ├─ APP_MODULE.xcodeproj
        │  │  └─ project.pbxproj
        │  ├─ Assets.xcassets
        │  │  ├─ AccentColor.colorset
        │  │  │  └─ Contents.json
        │  │  ├─ AppIcon.appiconset
        │  │  │  └─ Contents.json
        │  │  └─ Contents.json
        │  ├─ Entitlements.plist
        │  ├─ Info.plist
        │  └─ Sources
        │     └─ APP_MODULEAppMain.swift
        ├─ Package.swift
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ APP_MODULE
        │  │  ├─ APP_MODULEApp.swift
        │  │  ├─ ContentView.swift
        │  │  ├─ Resources
        │  │  │  ├─ Localizable.xcstrings
        │  │  │  └─ Module.xcassets
        │  │  │     └─ Contents.json
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ MODEL_MODULE
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           ├─ APP_MODULETests
           │  ├─ APP_MODULETests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ MODEL_MODULETests
              ├─ MODEL_MODULETests.swift
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
        XCTAssertTrue(AndroidManifest.contains("android.intent.category.LAUNCHER"))

        let SkipYML = try load("Sources/MODEL_MODULE/Skip/skip.yml")
        XCTAssertEqual(SkipYML, """
        # Configuration file for https://skip.tools project
        #
        # Kotlin dependencies and Gradle build options for this module can be configured here
        #build:
        #  contents:
        #    - block: 'dependencies'
        #      contents:
        #        - 'implementation("androidx.compose.runtime:runtime")'

        # this is a natively-compiled module
        skip:
          mode: native
          bridging: true
        
        """)

        let testCaseCode = try load("Tests/MODEL_MODULETests/MODEL_MODULETests.swift")
        XCTAssertEqual(testCaseCode, """
        import XCTest
        import OSLog
        import Foundation
        import SkipBridgeKt
        @testable import MODEL_MODULE

        let logger: Logger = Logger(subsystem: "MODEL_MODULE", category: "Tests")

        @available(macOS 13, *)
        final class MODEL_MODULETests: XCTestCase {
            override func setUp() {
                #if os(Android)
                // needed to load the compiled bridge from the traspiled tests
                loadPeerLibrary(packageName: "cool-app", moduleName: "MODEL_MODULE")
                #endif
            }

            func testMODEL_MODULE() throws {
                logger.log("running testMODEL_MODULE")
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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "APP_MODULEApp", type: .dynamic, targets: ["APP_MODULE"]),
                .library(name: "MODEL_MODULE", type: .dynamic, targets: ["MODEL_MODULE"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", "0.0.0"..<"2.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "APP_MODULE", dependencies: [
                    "MODEL_MODULE",
                    .product(name: "SkipUI", package: "skip-ui")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "APP_MODULETests", dependencies: [
                    "APP_MODULE",
                    .product(name: "SkipTest", package: "skip")
                ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "MODEL_MODULE", dependencies: [
                    .product(name: "SkipFuse", package: "skip-fuse"),
                    .product(name: "SkipModel", package: "skip-model")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "MODEL_MODULETests", dependencies: [
                    "MODEL_MODULE",
                    .product(name: "SkipTest", package: "skip")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )
        
        """)
    }

    func testLibInitAppFair() async throws {
        let projectName = "Free-App"

        let (projectURL, projectTree) = try await libInitComand(projectName: projectName, free: false, appfair: true) // appfair should override free
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
        │  │  └─ project.pbxproj
        │  ├─ Info.plist
        │  ├─ Sources
        │  │  └─ FreeAppAppMain.swift
        │  └─ fastlane
        │     ├─ AppStore.xcconfig
        │     ├─ Appfile
        │     ├─ Deliverfile
        │     ├─ Fastfile
        │     ├─ README.md
        │     └─ metadata
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
        ├─ LICENSE.GPL
        ├─ Package.swift
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
        // swift-tools-version: 5.9
        // This is a Skip (https://skip.tools) package,
        // containing a Swift Package Manager project
        // that will use the Skip build plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription

        let package = Package(
            name: "free-app-app",
            defaultLocalization: "en",
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "FreeAppApp", type: .dynamic, targets: ["FreeApp"]),
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
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", zero: true, tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "TOP_MODULE", "MIDDLE_MODULE", "BOTTOM_MODULE")
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
        │  │  └─ TOP_MODULEAppMain.swift
        │  ├─ TOP_MODULE.xcconfig
        │  └─ TOP_MODULE.xcodeproj
        │     └─ project.pbxproj
        ├─ Package.swift
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ BOTTOM_MODULE
        │  │  ├─ BOTTOM_MODULE.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ MIDDLE_MODULE
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  ├─ Skip
        │  │  │  └─ skip.yml
        │  │  └─ ViewModel.swift
        │  └─ TOP_MODULE
        │     ├─ ContentView.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ TOP_MODULEApp.swift
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
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "TOP_MODULEApp", type: .dynamic, targets: ["TOP_MODULE"]),
                .library(name: "MIDDLE_MODULE", type: .dynamic, targets: ["MIDDLE_MODULE"]),
                .library(name: "BOTTOM_MODULE", type: .dynamic, targets: ["BOTTOM_MODULE"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.0.0")
            ],
            targets: [
                .target(name: "TOP_MODULE", dependencies: [
                    "MIDDLE_MODULE"
                ] + (zero ? [] : [
                    .product(name: "SkipUI", package: "skip-ui")
                ]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "TOP_MODULETests", dependencies: [
                    "TOP_MODULE"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
                .target(name: "MIDDLE_MODULE", dependencies: [
                    "BOTTOM_MODULE"
                ] + (zero ? [] : [
                    .product(name: "SkipModel", package: "skip-model")
                ]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "MIDDLE_MODULETests", dependencies: [
                    "MIDDLE_MODULE"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
                .target(name: "BOTTOM_MODULE", dependencies: (zero ? [] : [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ]), resources: [.process("Resources")], plugins: skipstone),
                .testTarget(name: "BOTTOM_MODULETests", dependencies: [
                    "BOTTOM_MODULE"] + (zero ? [] : [.product(name: "SkipTest", package: "skip")]), resources: [.process("Resources")], plugins: skipstone),
            ]
        )

        """)
    }

    func testLibInitApp5ModuleNoZeroCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", zero: false, tests: false, fastlane: false, appid: "some.cool.app", moduleNames: "M1", "M2", "M3", "M4", "M5")
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
        │  │  └─ project.pbxproj
        │  └─ Sources
        │     └─ M1AppMain.swift
        ├─ Package.swift
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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "M1App", type: .dynamic, targets: ["M1"]),
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
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M2", dependencies: [
                    "M3",
                    .product(name: "SkipModel", package: "skip-model")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M3", dependencies: [
                    "M4"
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M4", dependencies: [
                    "M5"
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M5", dependencies: [
                    .product(name: "SkipFoundation", package: "skip-foundation")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
            ]
        )

        """)
    }

    func testLibInitApp5NativeModuleCommand() async throws {
        let (projectURL, projectTree) = try await libInitComand(projectName: "cool-app", zero: false, native: true, tests: true, fastlane: false, appid: "some.cool.app", moduleNames: "M1", "M2", "M3", "M4", "M5")
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
        │  │  └─ project.pbxproj
        │  └─ Sources
        │     └─ M1AppMain.swift
        ├─ Package.swift
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
        │  │  ├─ Skip
        │  │  │  └─ skip.yml
        │  │  └─ ViewModel.swift
        │  ├─ M3
        │  │  └─ M3.swift
        │  ├─ M4
        │  │  └─ M4.swift
        │  └─ M5
        │     └─ M5.swift
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
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let load = { try String(contentsOf: URL(fileURLWithPath: $0, isDirectory: false, relativeTo: projectURL)) }
        let AndroidManifest = try load("Android/app/src/main/AndroidManifest.xml")
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
            platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10), .macCatalyst(.v17)],
            products: [
                .library(name: "M1App", type: .dynamic, targets: ["M1"]),
                .library(name: "M2", type: .dynamic, targets: ["M2"]),
                .library(name: "M3", type: .dynamic, targets: ["M3"]),
                .library(name: "M4", type: .dynamic, targets: ["M4"]),
                .library(name: "M5", type: .dynamic, targets: ["M5"]),
            ],
            dependencies: [
                .package(url: "https://source.skip.tools/skip.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-ui.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-model.git", from: "1.0.0"),
                .package(url: "https://source.skip.tools/skip-fuse.git", "0.0.0"..<"2.0.0")
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
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .testTarget(name: "M2Tests", dependencies: [
                    "M2",
                    .product(name: "SkipTest", package: "skip")
                ], plugins: [.plugin(name: "skipstone", package: "skip")]),
                .target(name: "M3", dependencies: [
                    "M4"
                ]),
                .target(name: "M4", dependencies: [
                    "M5"
                ]),
                .target(name: "M5", dependencies: []),
            ]
        )

        """)
    }

    func libInitComand(projectName: String, free: Bool? = nil, zero: Bool? = nil, appfair: Bool? = nil, native: Bool? = nil, tests moduleTests: Bool? = nil, fastlane: Bool? = nil, validatePackage: Bool? = true, appid: String? = nil, resourcePath: String? = "Resources", iconColor: String? = nil, moduleNames: String...) async throws -> (projectURL: URL, projectTree: String?) {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory() + "/testLibInitCommand/", isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        var cmd = ["lib", "init", "-jA", "--no-build", "--no-test", "--show-tree"]
        if let resourcePath = resourcePath {
            cmd += ["--resource-path", resourcePath]
        }

        cmd += ["--icon-color", iconColor ?? ""]

        if zero == true {
            cmd += ["--zero"]
        } else if zero == false {
            cmd += ["--no-zero"]
        }

        // conventional Skip apps
        if appfair == true {
            cmd += ["--appfair"]
        } else if appfair == false {
            cmd += ["--no-appfair"]
        }

        if native == true {
            cmd += ["--native"]
        } else if native == false {
            cmd += ["--no-native"]
        }

        if moduleTests == true {
            cmd += ["--module-tests"]
        } else if moduleTests == false {
            cmd += ["--no-module-tests"]
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

        let created = try await skipstone(cmd).json()
        XCTAssertEqual(created.array?.first, ["msg": .string("Initializing Skip \(appid == nil ? "library" : "application") \(projectName)")])
        // return the tree output, which is in the 2nd-to-last message
       return (projectURL: tmpDir.appendingPathComponent(projectName, isDirectory: true), projectTree: created.array?.dropLast(2).last?["msg"]?.string)
    }
}


/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
