// Copyright 2023–2025 Skip
import XCTest
import SkipDrive

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
class SkipCommandTests : XCTestCase {
    func testSkipVersion() async throws {
        var versionOut = try await skip("version").out
        if versionOut.hasSuffix(" (debug)") {
            versionOut.removeLast(" (debug)".count)
        }

        // this fails when building against a non-released version of skip
        //XCTAssertEqual("Skip version \(SkipDrive.skipVersion)", versionOut)
        XCTAssertTrue(versionOut.hasPrefix("Skip version "), "Version output should start with 'Skip version ': \(versionOut)")
    }

    func testSkipVersionJSON() async throws {
        let version = try await skip("version", "--json").out.parseJSONObject()["version"] as? String
        // this fails when building against a non-released version of skip
        // try await XCTAssertEqualAsync(SkipDrive.skipVersion, version)
        XCTAssertNotNil(version)
    }

    func testSkipWelcome() async throws {
        try await skip("welcome")
    }

    func testSkipWelcomeJSON() async throws {
        let welcome = try await skip("welcome", "--json", "--json-array").out.parseJSONArray()
        XCTAssertNotEqual(0, welcome.count, "Welcome message should not be empty")
    }

    func DISABLEDtestSkipDoctor() async throws {
        // run `skip doctor` with JSON array output and make sure we can parse the result
        let doctor = try await skip("doctor", "-jA", "-v").out.parseJSONMessages()
        XCTAssertGreaterThan(doctor.count, 5, "doctor output should have contained some lines")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("macOS version") }), "missing macOS version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Swift version") }), "missing Swift version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Xcode version") }), "missing Xcode version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Xcode tools") }), "missing Xcode tools")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Homebrew version") }), "missing Homebrew version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Gradle version") }), "missing Gradle version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Java version") }), "missing Java version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Android Debug Bridge version") }), "missing Android Debug Bridge version")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Android tools SDKs:") }), "missing Android SDKs")
        XCTAssertTrue(doctor.contains(where: { $0.hasPrefix("Check Skip Updates") }), "missing Check Skip Updates")
    }

    func testSkipDevices() async throws {
        let devices = try await skip("devices", "-jA").out.parseJSONArray()
        XCTAssertGreaterThanOrEqual(devices.count, 0)
    }

    func DISABLEDtestSkipCheckup() async throws {
        let checkup = try await skip("checkup", "-jA").out.parseJSONMessages()
        XCTAssertGreaterThan(checkup.count, 5, "checkup output should have contained some lines")
    }

    func testSkipCreate() async throws {
        let tempDir = try mktmp()
        let projectName = "hello-skip"
        let dir = tempDir + "/" + projectName + "/"
        let appName = "HelloSkip"
        let out = try await skip("init", "-jA", "-v", "--show-tree", "-d", dir, "--transpiled-app", "--appid", "com.company.HelloSkip", projectName, appName)
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip application \(projectName)", msgs.first)

        let xcodeproj = "Darwin/" + appName + ".xcodeproj"
        let xcconfig = "Darwin/" + appName + ".xcconfig"
        for path in ["Package.swift", xcodeproj, xcconfig, "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
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
        │  ├─ HelloSkip.xcconfig
        │  ├─ HelloSkip.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ HelloSkip App.xcscheme
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
        ├─ Package.resolved
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ HelloSkip
        │     ├─ ContentView.swift
        │     ├─ HelloSkipApp.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           └─ HelloSkipTests
              ├─ HelloSkipTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)
    }

    func testSkipIcon() async throws {
        let tempDir = try mktmp()
        let name = "demo-app"
        let dir = tempDir + "/" + name + "/"
        let appName = "Demo"
        // generate an app scaffold without building it, just so we can see what the file tree looks like
        let createApp = { try await self.skip("init", "-jA", "--show-tree", "--no-icon", "--no-build", "--zero", "--free", "-v", "-d", dir, "--transpiled-app", "--appid", "demo.app.App", name, appName) }
        var out = try await createApp()
        var msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip application \(name)", msgs.first)

        let xcodeproj = "Darwin/" + appName + ".xcodeproj"
        let xcconfig = "Darwin/" + appName + ".xcconfig"
        for path in ["Package.swift", xcodeproj, xcconfig, "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        // we first create an app with --no-icon
        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
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
        │  ├─ Demo.xcconfig
        │  ├─ Demo.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ Demo App.xcscheme
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
        ├─ LICENSE.GPL
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ Demo
        │     ├─ ContentView.swift
        │     ├─ DemoApp.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           └─ DemoTests
              ├─ DemoTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        let pngData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAAHElEQVQI12P4//8/w38GIAXDIBKE0DHxgljNBAAO9TXL0Y4OHwAAAABJRU5ErkJggg==") // little red dot

        // generating icons from a PNG will just create a single ic_launcher.png, but not separate foreground and background images
        let miniPNG = "\(dir)/empty.png"
        XCTAssertTrue(FileManager.default.createFile(atPath: miniPNG, contents: pngData))

        // first create *only* for Dawrwin
        let _ = try await skip("icon", "-jA", "--darwin", "-d", dir, miniPNG)

        out = try await createApp()
        msgs = try out.out.parseJSONMessages()

        // we re-init in the same folder simply to get the file tree again (which `skip icon` doesn't have an option for) to validate that the icons were generated
        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
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
        │  ├─ Demo.xcconfig
        │  ├─ Demo.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ Demo App.xcscheme
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
        ├─ LICENSE.GPL
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ Demo
        │     ├─ ContentView.swift
        │     ├─ DemoApp.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        ├─ Tests
        │  └─ DemoTests
        │     ├─ DemoTests.swift
        │     ├─ Resources
        │     │  └─ TestData.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ XCSkipTests.swift
        └─ empty.png
        
        """)

        // now create for Darwin + Android
        let _ = try await skip("icon", "-jA", "-d", dir, miniPNG)

        out = try await createApp()
        msgs = try out.out.parseJSONMessages()

        // we re-init in the same folder simply to get the file tree again (which `skip icon` doesn't have an option for) to validate that the icons were generated
        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
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
        │  │           ├─ mipmap-hdpi
        │  │           │  └─ ic_launcher.png
        │  │           ├─ mipmap-mdpi
        │  │           │  └─ ic_launcher.png
        │  │           ├─ mipmap-xhdpi
        │  │           │  └─ ic_launcher.png
        │  │           ├─ mipmap-xxhdpi
        │  │           │  └─ ic_launcher.png
        │  │           └─ mipmap-xxxhdpi
        │  │              └─ ic_launcher.png
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
        │  ├─ Demo.xcconfig
        │  ├─ Demo.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ Demo App.xcscheme
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
        ├─ LICENSE.GPL
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ Demo
        │     ├─ ContentView.swift
        │     ├─ DemoApp.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        ├─ Tests
        │  └─ DemoTests
        │     ├─ DemoTests.swift
        │     ├─ Resources
        │     │  └─ TestData.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ XCSkipTests.swift
        └─ empty.png
        
        """)

        // generating random icons will create two layers in the Android folder: ic_launcher_background.png and ic_launcher_foreground.png
        let _ = try await skip("icon", "-jA", "-d", dir, "--random-icon")

        out = try await createApp()
        msgs = try out.out.parseJSONMessages()

        // we re-init in the same folder simply to get the file tree again (which `skip icon` doesn't have an option for) to validate that the icons were generated
        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
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
        │  ├─ Demo.xcconfig
        │  ├─ Demo.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ Demo App.xcscheme
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
        ├─ LICENSE.GPL
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  └─ Demo
        │     ├─ ContentView.swift
        │     ├─ DemoApp.swift
        │     ├─ Resources
        │     │  ├─ Localizable.xcstrings
        │     │  └─ Module.xcassets
        │     │     └─ Contents.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        ├─ Tests
        │  └─ DemoTests
        │     ├─ DemoTests.swift
        │     ├─ Resources
        │     │  └─ TestData.json
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ XCSkipTests.swift
        └─ empty.png

        """)

    }

    func testSkipFair() async throws {
        let tempDir = try mktmp()
        let projectName = "hello-skip"
        let dir = tempDir + "/" + projectName + "/"
        let appName = "HelloSkip"
        let modelName = "HelloSkipModel"
        let out = try await skip("init", "-jA", "-v", "--show-tree", "-d", dir, "--transpiled-app", "--appfair", projectName, appName, modelName)
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip application \(projectName)", msgs.first)

        let xcodeproj = "Darwin/" + appName + ".xcodeproj"
        let xcconfig = "Darwin/" + appName + ".xcconfig"
        for path in ["Package.swift", xcodeproj, xcconfig, "Sources", "Tests"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
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
        │  ├─ HelloSkip.xcconfig
        │  ├─ HelloSkip.xcodeproj
        │  │  ├─ project.pbxproj
        │  │  └─ xcshareddata
        │  │     └─ xcschemes
        │  │        └─ HelloSkip App.xcscheme
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
        ├─ LICENSE.GPL
        ├─ Package.resolved
        ├─ Package.swift
        ├─ Project.xcworkspace
        │  └─ contents.xcworkspacedata
        ├─ README.md
        ├─ Skip.env
        ├─ Sources
        │  ├─ HelloSkip
        │  │  ├─ ContentView.swift
        │  │  ├─ HelloSkipApp.swift
        │  │  ├─ Resources
        │  │  │  ├─ Localizable.xcstrings
        │  │  │  └─ Module.xcassets
        │  │  │     └─ Contents.json
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ HelloSkipModel
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ ViewModel.swift
        └─ Tests
           ├─ HelloSkipModelTests
           │  ├─ HelloSkipModelTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ HelloSkipTests
              ├─ HelloSkipTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)

        // make sure we can export it
        try await checkExport(app: true, moduleName: appName, dir: dir)
    }

    func testSkipInit() async throws {
        let tempDir = try mktmp()
        let name = "cool-lib"
        let dir = tempDir + "/" + name + "/"
        let out = try await skip("init", "-jA", "-v", "--show-tree", "--transpiled-model", "-d", dir, name, "CoolA", "CoolB", "CoolC", "CoolD", "CoolE")
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip library \(name)", msgs.first)

        for path in ["Package.swift", "Sources/CoolA", "Sources/CoolA", "Sources/CoolE", "Tests", "Tests/CoolATests/Skip/skip.yml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual(name, project.name)

        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
        .
        ├─ Package.resolved
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  ├─ CoolA
        │  │  ├─ CoolA.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ CoolB
        │  │  ├─ CoolB.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ CoolC
        │  │  ├─ CoolC.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  ├─ CoolD
        │  │  ├─ CoolD.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     └─ skip.yml
        │  └─ CoolE
        │     ├─ CoolE.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           ├─ CoolATests
           │  ├─ CoolATests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ CoolBTests
           │  ├─ CoolBTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ CoolCTests
           │  ├─ CoolCTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           ├─ CoolDTests
           │  ├─ CoolDTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ CoolETests
              ├─ CoolETests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)
    }

    func testSkipInitGit() async throws {
        let tempDir = try mktmp()
        let name = "neat-lib"
        let dir = tempDir + "/" + name + "/"
        let out = try await skip("init", "-jA", "-v", "--git-repo", "--show-tree", "--transpiled-model", "-d", dir, name, "NeatA")
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip library \(name)", msgs.first)

        for path in [
            "Package.swift",
            "Sources/NeatA",
            "Tests",
            "Tests/NeatATests/Skip/skip.yml",
            ".gitignore",
            ".git/config",
        ] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual(name, project.name)

        XCTAssertEqual(msgs.dropLast(2).last ?? "", """
        .
        ├─ Package.resolved
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ NeatA
        │     ├─ NeatA.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           └─ NeatATests
              ├─ NeatATests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift

        """)
    }

    func testSkipExportFramework() async throws {
        let tempDir = try mktmp()
        let name = "demo-framework"
        let dir = tempDir + "/" + name + "/"
        let moduleName = "DemoFramework"
        let out = try await skip("init", "-jA", "--show-tree", "-v", "--transpiled-model", "-d", dir, name, moduleName)
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip library \(name)", msgs.first)

        for path in ["Package.swift", "Sources/DemoFramework", "Tests", "Tests/DemoFrameworkTests/Skip/skip.yml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        try await checkExport(app: false, moduleName: moduleName, dir: dir)
    }

    func testSkipExportApp() async throws {
        let tempDir = try mktmp()
        let name = "demo-app"
        let dir = tempDir + "/" + name + "/"
        let appName = "Demo"
        let out = try await skip("init", "-jA", "--show-tree", "--zero", "--free", "-v", "-d", dir, "--transpiled-app", "--appid", "demo.app.App", name, appName)
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip application \(name)", msgs.first)

        for path in ["Package.swift", "Sources/Demo", "Tests", "Tests/DemoTests/Skip/skip.yml"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        try await checkExport(app: true, moduleName: appName, dir: dir)
    }

    /// This works, but it is very slow, and also required installing the Android toolchain on the Skip CI host
    func DISABLEDtestSkipExportAppNative() async throws {
        let tempDir = try mktmp()
        let name = "demo-app-native"
        let dir = tempDir + "/" + name + "/"
        // create a three-module native app
        let out = try await skip("init", "-jA", "--show-tree", "--free", "-v", "-d", dir, "--native-app", "--appid", "demo.app.App", name, "Demo", "DemoModel", "DemoLogic")
        let msgs = try out.out.parseJSONMessages()

        XCTAssertEqual("Initializing Skip application \(name)", msgs.first)

        for path in ["Package.swift", "Sources/Demo"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir + path), "missing file at: \(path)")
        }

        let project = try await loadProjectPackage(dir)
        XCTAssertEqual(name, project.name)

        let exportPath = try mktmp()
        let exported = try await skip("export", "-jA", "-v", "--show-tree", "--project", dir, "-d", exportPath)
        let exportedJSON = try exported.out.parseJSONMessages()
        let fileTree = exportedJSON.dropLast(1).last ?? ""

        XCTAssertTrue(fileTree.contains("Demo-debug.apk"), "missing expected Demo-debug.apk in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-release.apk"), "missing expected Demo-release.apk in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-debug.aab"), "missing expected Demo-debug.aab in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-release.aab"), "missing expected Demo-release.aab in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-debug.ipa"), "missing expected Demo-debug.ipa in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-release.ipa"), "missing expected Demo-release.ipa in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-debug.xcarchive.zip"), "missing expected Demo-debug.xcarchive.zip in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-release.xcarchive.zip"), "missing expected Demo-release.xcarchive.zip in \(fileTree)")
        XCTAssertTrue(fileTree.contains("Demo-project.zip"), "missing expected Demo-project.zip in \(fileTree)")
    }

    func DISABLEDtestSkipTestReport() async throws {
        // hangs when running from the CLI
        let xunit = try mktmpFile(contents: Data(xunitResults.utf8))
        let tempDir = try mktmp()
        let junit = tempDir + "/" + "testDebugUnitTest"
        try FileManager.default.createDirectory(atPath: junit, withIntermediateDirectories: true)
        try Data(junitResults.utf8).write(to: URL(fileURLWithPath: junit + "/TEST-skip.zip.SkipZipTests.xml"))

        // .build/plugins/outputs/skip-zip/SkipZipTests/skipstone/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
        let report = try await skip("test", "--configuration", "debug", "--test", "--max-column-length", "15", "--xunit", xunit, "--junit", junit)
        XCTAssertEqual(report.out, """
        | Test         | Case            | Swift | Kotlin |
        | ------------ | --------------- | ----- | ------ |
        | SkipZipTests | testArchive     | PASS  | SKIP   |
        | SkipZipTests | testDeflateInfl | PASS  | PASS   |
        | SkipZipTests | testMissingTest | PASS  | ????   |
        |              |                 | 100%  | 33%    |
        """)
    }

    func checkExport(app: Bool, moduleName: String, dir: String, debug: Bool = true, release: Bool = true) async throws {
        let project = try await loadProjectPackage(dir)
        XCTAssertNotEqual(0, project.products.count)
        //XCTAssertEqual(appName, project.name)

        let exportPath = try mktmp()
        let config = debug && !release ? "--debug" : release && !debug ? "--release" : "-v"

        let exported = try await skip("export", "-jA", "-v", "--show-tree", config, "--project", dir, "-d", exportPath)
        let exportedJSON = try exported.out.parseJSONMessages()
        let fileTree = exportedJSON.dropLast(1).last ?? ""

        func checkArtifacts(type: String) throws {
            if app {
                XCTAssertTrue(fileTree.contains("\(moduleName)-\(type).apk"), "missing expected \(moduleName)-\(type).apk in \(fileTree)")
                XCTAssertTrue(fileTree.contains("\(moduleName)-\(type).aab"), "missing expected \(moduleName)-\(type).aab in \(fileTree)")
                XCTAssertTrue(fileTree.contains("\(moduleName)-\(type).ipa"), "missing expected \(moduleName)-\(type).ipa in \(fileTree)")
                XCTAssertTrue(fileTree.contains("\(moduleName)-\(type).xcarchive.zip"), "missing expected \(moduleName)-\(type).xcarchive.zip in \(fileTree)")
            } else {
                XCTAssertTrue(fileTree.contains("\(moduleName)-\(type).aar"), "missing expected \(moduleName)-\(type).aar in \(fileTree)")
                XCTAssertTrue(fileTree.contains("SkipFoundation-\(type).aar"), "missing expected SkipFoundation-\(type).aar in \(fileTree)")
            }
        }

        if debug {
            try checkArtifacts(type: "debug")
        }

        if release {
            try checkArtifacts(type: "release")
        }

        XCTAssertTrue(fileTree.contains("\(moduleName)-project.zip"), "missing expected \(moduleName)-project.zip in \(fileTree)")
    }

    /// Runs the tool with the given arguments, returning the entire output string as well as a function to parse it to `JSON`
    @discardableResult func skip(checkError: Bool = true, printOutput: Bool = true, _ args: String...) async throws -> (out: String, err: String) {
        // turn "-[SkipCommandTests testSomeTest]" into "testSomeTest"
        let testName = testRun?.test.name.split(separator: " ").last?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) ?? "TEST"

        // the default SPM location of the current skip CLI for testing
        var skiptools = [
            ".build/artifacts/skip/skip/skip.artifactbundle/macos/skip",
            ".build/plugins/tools/debug/skip", // the SKIPLOCAL build path macOS 14-
            ".build/debug/skip", // the SKIPLOCAL build path macOS 15+
        ]

        // when running tests from Xcode, we need to use the tool download folder, which seems to be placed in one of the environment property `__XCODE_BUILT_PRODUCTS_DIR_PATHS`, so check those folders and override if skip is found
        for checkFolder in (ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? "").split(separator: ":") {
            let xcodeSkipPath = checkFolder.description + "/skip"
            if FileManager.default.isExecutableFile(atPath: xcodeSkipPath) {
                skiptools.append(xcodeSkipPath)
            }
        }

        struct SkipLaunchError : LocalizedError { var errorDescription: String? }

        guard let skiptool = skiptools.last(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw SkipLaunchError(errorDescription: "Could not locate the skip executable in any of the paths: \(skiptools.joined(separator: " "))")
        }

        let cmd = [skiptool] + args
        if printOutput {
            print("running: \(cmd.joined(separator: " "))")
        }

        var outputLines: [AsyncLineOutput.Element] = []
        var result: ProcessResult? = nil
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb" // override TERM to prevent skip from using ANSI colors or progress animations
        env["SKIPLOCAL"] = nil // need to clear the sub-process SKIPLOCAL, since remote dependencies cannot use local paths (https://forums.swift.org/t/unable-to-integrate-a-remote-package-that-has-local-packages/53146/17)

        for try await outputLine in Process.streamLines(command: cmd, environment: env, includeStdErr: true, onExit: { result = $0 }) {
            if printOutput {
                print("\(testName) [\(outputLine.err ? "stderr" : "stdout")]> \(outputLine.line)")
            }
            outputLines.append(outputLine)
        }

        guard let result = result else {
            throw SkipLaunchError(errorDescription: "command did not exit: \(cmd)")
        }

        let stdoutString = outputLines.filter({ $0.err == false }).map(\.line).joined(separator: "\n")
        let stderrString = outputLines.filter({ $0.err == true }).map(\.line).joined(separator: "\n")

        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            XCTFail("error running command: \(cmd)\nenvironment:\n    \(env.sorted(by: { $0.key < $1.key }).map({ $0.key + ": " + $0.value }).joined(separator: "\n    "))\nSTDERR: \(stderrString)")
            throw ProcessResult.Error.nonZeroExit(result)
        }

        return (out: stdoutString, err: stderrString)
    }

}

/// A JSON object
typealias JSONObject = [String: Any]

private extension String {
    /// Attempts to parse the given String as a JSON object
    func parseJSONObject(file: StaticString = #file, line: UInt = #line) throws -> JSONObject {
        do {
            let json = try JSONSerialization.jsonObject(with: Data(utf8), options: [])
            if let obj = json as? JSONObject {
                return obj
            } else {
                struct CannotParseJSONIntoObject : LocalizedError { var errorDescription: String? }
                throw CannotParseJSONIntoObject(errorDescription: "JSON object was of wrong type: \(type(of: json))")
            }
        } catch {
            XCTFail("Error parsing JSON Object from: \(self)", file: file, line: line)
            throw error
        }
    }

    /// Attempts to parse the given String as a JSON object
    func parseJSONArray(file: StaticString = #file, line: UInt = #line) throws -> [Any] {
        var str = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // workround for test failures: sometimes stderr has a line line: "2023-10-27 17:04:18.587523-0400 skip[91666:2692850] [client] No error handler for XPC error: Connection invalid"; this seems to be a side effect of running `skip doctor` from within Xcode
        if str.hasSuffix("No error handler for XPC error: Connection invalid") {
            str = str.split(separator: "\n").dropLast().joined(separator: "\n")
        }

        do {
            let json = try JSONSerialization.jsonObject(with: Data(utf8), options: [])
            if let arr = json as? [Any] {
                return arr
            } else {
                struct CannotParseJSONIntoArray : LocalizedError { var errorDescription: String? }
                throw CannotParseJSONIntoArray(errorDescription: "JSON object was of wrong type: \(type(of: json))")
            }
        } catch {
            XCTFail("Error parsing JSON Array from: \(self)", file: file, line: line)
            throw error
        }
    }

    func parseJSONMessages(file: StaticString = #file, line: UInt = #line) throws -> [String] {
        try parseJSONArray(file: file, line: line).compactMap({ ($0 as? JSONObject)?["msg"] as? String })
    }
}

/// Create a temporary directory
func mktmp(baseName: String = "SkipDriveTests") throws -> String {
    let tempDir = [NSTemporaryDirectory(), baseName, UUID().uuidString].joined(separator: "/")
    try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
    return tempDir
}

/// Create a temporary directory
func mktmpFile(baseName: String = "SkipDriveTests", named: String = "file-\(UUID().uuidString)", contents: Data) throws -> String {
    let tempDir = try mktmp(baseName: baseName)
    let tempFile = tempDir + "/" + named
    try contents.write(to: URL(fileURLWithPath: tempFile), options: .atomic)
    return tempFile
}

func loadProjectPackage(_ path: String) async throws -> PackageManifest {
    try await execJSON(["swift", "package", "dump-package", "--package-path", path])
}

func loadProjectConfig(_ path: String, scheme: String? = nil) async throws -> [ProjectBuildSettings] {
    try await execJSON(["xcodebuild", "-showBuildSettings", "-json", "-project", path] + (scheme == nil ? [] : ["-scheme", scheme!]))
}

func execJSON<T: Decodable>(_ arguments: [String]) async throws -> T {
    let output = try await Process.checkNonZeroExit(arguments: arguments, loggingHandler: nil)
    return try JSONDecoder().decode(T.self, from: Data(output.utf8))
}

/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}



/// An incomplete representation of package JSON, to be filled in as needed for the purposes of the tool
/// The output from `swift package dump-package`.
struct PackageManifest : Hashable, Decodable {
    var name: String
    //var toolsVersion: String // can be string or dict
    var products: [Product]
    var dependencies: [Dependency]
    //var targets: [Either<Target>.Or<String>]
    var platforms: [SupportedPlatform]
    var cModuleName: String?
    var cLanguageStandard: String?
    var cxxLanguageStandard: String?

    struct Target: Hashable, Decodable {
        enum TargetType: String, Hashable, Decodable {
            case regular
            case test
            case system
        }

        var `type`: TargetType
        var name: String
        var path: String?
        var excludedPaths: [String]?
        //var dependencies: [String]? // dict
        //var resources: [String]? // dict
        var settings: [String]?
        var cModuleName: String?
        // var providers: [] // apt, brew, etc.
    }


    struct Product : Hashable, Decodable {
        //var `type`: ProductType // can be string or dict
        var name: String
        var targets: [String]

        enum ProductType: String, Hashable, Decodable, CaseIterable {
            case library
            case executable
        }
    }

    struct Dependency : Hashable, Decodable {
        var name: String?
        var url: String?
        //var requirement: Requirement // revision/range/branch/exact
    }

    struct SupportedPlatform : Hashable, Decodable {
        var platformName: String
        var version: String
    }
}


/// The output from `xcodebuild -showBuildSettings -json -project Project.xcodeproj -scheme SchemeName`
struct ProjectBuildSettings : Decodable {
    let target: String
    let action: String
    let buildSettings: [String: String]
}




// sample test output generated with the following command in the skip-zip package:
// swift test --enable-code-coverage --parallel --xunit-output=.build/swift-xunit.xml --filter=SkipZipTests

// .build/plugins/outputs/skip-zip/SkipZipTests/skipstone/SkipZip/.build/SkipZip/test-results/testDebugUnitTest/TEST-skip.zip.SkipZipTests.xml
let junitResults = """
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="skip.zip.SkipZipTests" tests="2" skipped="1" failures="0" errors="0" timestamp="2023-08-23T16:53:50" hostname="zap.local" time="0.02">
  <properties/>
  <testcase name="testDeflateInflate" classname="skip.zip.SkipZipTests" time="0.019"/>
  <testcase name="testArchive$SkipZip_debugUnitTest" classname="skip.zip.SkipZipTests" time="0.001">
    <skipped/>
  </testcase>
  <system-out><![CDATA[]]></system-out>
  <system-err><![CDATA[Aug 23, 2023 12:53:50 PM skip.foundation.SkipLogger log
INFO: running test
]]></system-err>
</testsuite>
"""

// .build/swift-xunit.xml
let xunitResults = """
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
<testsuite name="TestResults" errors="0" tests="4" failures="0" time="15.553686000999999">
<testcase classname="SkipZipTests.SkipZipTests" name="testDeflateInflate" time="0.047230875">
</testcase>
<testcase classname="SkipZipTests.SkipZipTests" name="testArchive" time="7.729590584">
</testcase>
<testcase classname="SkipZipTests.SkipZipTests" name="testMissingTest" time="0.01">
</testcase>
<testcase classname="SkipZipTests.XCSkipTest" name="testSkipModule" time="7.729628">
</testcase>
</testsuite>
</testsuites>
"""
