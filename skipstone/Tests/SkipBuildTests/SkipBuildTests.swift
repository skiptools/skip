// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import SkipBuild

final class SkipBuildTests: XCTestCase {
    func testANSIColors() {
        XCTAssertEqual(0, Term.stripANSIAttributes(from: "").count)
        XCTAssertEqual(1, Term.stripANSIAttributes(from: "A").count)

        XCTAssertEqual(12, Term(colors: true).green("ABC").count)
        XCTAssertEqual(3, Term.stripANSIAttributes(from: Term(colors: true).green("ABC")).count)
    }

    func testSHA256() throws {
        do {
            let tmpFile = URL(fileURLWithPath: NSTemporaryDirectory().appending("/" + UUID().uuidString))
            try "Hello World".write(to: tmpFile, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tmpFile) }
            XCTAssertEqual("a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e", try tmpFile.SHA256Hash())
        }

        do {
            let msg = "".data(using: .utf8)!
            let result = msg.SHA256Hash()
            let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // echo -n "" | openssl dgst -sha256
            XCTAssertEqual(result, expected, "Invalid conversion from msg to sha256")
        }

        do {
            let msg = "foobar".data(using: .utf8)!
            let result = msg.SHA256Hash()
            let expected = "c3ab8ff13720e8ad9047dd39466b3c8974e592c2fa383d4a3960714caef0c4f2" // echo -n "foobar" | openssl dgst -sha256
            XCTAssertEqual(result, expected, "Invalid conversion from msg to sha256")
        }

        do {
            let msg = "æøå".data(using: .utf8)!
            let result = msg.SHA256Hash()
            let expected = "6c228cdba89548a1af198f33819536422fb01b66e51f761cf2ec38d1fb4178a6" // echo -n "æøå" | openssl dgst -sha256
            XCTAssertEqual(result, expected, "Invalid conversion from msg to sha256")
        }

        do {
            let msg = "KfZ=Day*q4MsZ=_xRy4G_Uefk?^Ytr&2xL*RYY%VLyB_&c7R_dr&J+8A79suf=^".data(using: .utf8)!
            let result = msg.SHA256Hash()
            let expected = "b754632a872b3f5ddb0e1e24b531e35eb334ee3c2957618ac4a2ac4047ed6127" // echo -n "KfZ=Day*q4MsZ=_xRy4G_Uefk?^Ytr&2xL*RYY%VLyB_&c7R_dr&J+8A79suf=^" | openssl dgst -sha256
            XCTAssertEqual(result, expected, "Invalid conversion from msg to sha256")
        }

        do {
            let msg = "Lorem ipsum dolor sit amet, suas consequuntur mei ad, duo eu noluisse adolescens temporibus. Mutat fuisset constituam te vis. Animal meliore cu has, ius ad recusabo complectitur. Eam at persius inermis sensibus. Mea at velit nobis dolor, vitae omnium eos an, ei dolorum pertinacia nec.".data(using: .utf8)!
            let result = msg.SHA256Hash()
            let expected = "31902eb17aa07165b645553c14b985c1908c7d8f4f5178de61a3232f09940df7" // echo -n "Lorem ipsum dolor sit amet, suas consequuntur mei ad, duo eu noluisse adolescens temporibus. Mutat fuisset constituam te vis. Animal meliore cu has, ius ad recusabo complectitur. Eam at persius inermis sensibus. Mea at velit nobis dolor, vitae omnium eos an, ei dolorum pertinacia nec." | openssl dgst -sha256
            XCTAssertEqual(result, expected, "Invalid conversion from msg to sha256")
        }

        do {
            let msg = "0".data(using: .utf8)!
            let result = msg.SHA256Hash()
            let expected = "5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9" // echo -n "0" | openssl dgst -sha256
            XCTAssertEqual(result, expected, "Invalid conversion from msg to sha256")
        }
    }

    func testPadString() {
        XCTAssertEqual("a", "abc".pad(1))
        XCTAssertEqual("ab", "abc".pad(2))
        XCTAssertEqual("abc", "abc".pad(3))
        XCTAssertEqual("abc ", "abc".pad(4))
        XCTAssertEqual("abc  ", "abc".pad(5))
    }

    func testExtract() throws {
        XCTAssertEqual("c", try "abc".extract(pattern: "ab(.*)"))
        XCTAssertEqual("345", try "12345 abc".extract(pattern: "12([0-9]+)"))
    }

    func testRegex() throws {
        XCTAssertEqual(["345"], try NSRegularExpression(pattern: "12([0-9]+)").extract(from: "12345 abc"))
        XCTAssertEqual(nil, try NSRegularExpression(pattern: "([a-zA-Z]+)([0-9]+)").extract(from: ""))
        XCTAssertEqual(["A", "1"], try NSRegularExpression(pattern: "([a-zA-Z]+)([0-9]+)").extract(from: "A1"))
        XCTAssertEqual(["xA", "19"], try NSRegularExpression(pattern: "([a-zA-Z]+)\\s([0-9]+)").extract(from: "xA 19"))
    }

    func testSlide() {
        XCTAssertEqual(["A"], ["A"].slice(0))
        XCTAssertEqual([], ["A"].slice(1))
        XCTAssertEqual(["A"], ["A"].slice(0, 1))
        XCTAssertEqual(["A"], ["A"].slice(0, 9))
        XCTAssertEqual([], ["A"].slice(1, 2))
        XCTAssertEqual([], ["A"].slice(5))
        XCTAssertEqual([], ["A"].slice(8, 3))

        XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].slice(0))
        XCTAssertEqual([1, 2, 3, 4, 5, 6, 7, 8, 9], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].slice(1))
        XCTAssertEqual([0], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].slice(0, 1))
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 7, 8], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].slice(0, 9))
        XCTAssertEqual([1], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].slice(1, 2))
        XCTAssertEqual([5, 6, 7, 8, 9], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].slice(5))
    }

    func testCreateIcon() async throws {
        #if canImport(ImageIO)
        for size in [10, 100, 1024] {
            do { // square
                let expectedIconSize = size == 10 ? 250 : size == 100 ? 4591 : 208601 // note: implementation details may change
                let iconData = try await createAppIcon(width: size, height: size, circular: false, foreground: nil, backgroundColors: ["#4994EC"], foregroundColor: nil, iconSources: [], iconShadow: nil, iconInset: 0.02)
                XCTAssertEqual(iconData.count, expectedIconSize)
            }

            do { // circular
                let expectedIconSize = size == 10 ? 291 : size == 100 ? 5262 : 262667 // note: implementation details may change
                let iconData = try await createAppIcon(width: size, height: size, circular: true, foreground: nil, backgroundColors: ["#ABABAB"], foregroundColor: nil, iconSources: [], iconShadow: nil, iconInset: 0.02)
                XCTAssertEqual(iconData.count, expectedIconSize)
            }
        }

        setenv("CORESVG_VERBOSE", "1", 1)
        XCTAssertNil(SVG("<XXX></XXX>"), "should not have been able to create invalid SVG") // CoreSVG: Error: Reader: Error on line 0: Root XML node does not have "SVG" type

        let svg1 = try XCTUnwrap(SVG("<svg width='12' height='12'></svg>"), "could not create SVG")
        XCTAssertEqual(12.0, svg1.size.width)
        XCTAssertEqual(12.0, svg1.size.height)

        let svg2 = try XCTUnwrap(SVG(MaterialIcon.icon_chess.rawValue), "could not create SVG")
        XCTAssertEqual(40.0, svg2.size.width)
        #endif
    }

    func testParseXCConfig() {
        let keyValues = parseXCConfig(contents: """
        # Comment
        A = B

        // Comment 2
        Some Key   =   __somevalue;;;
        """)

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: keyValues), [
            "A": "B",
            "Some Key": "__somevalue;;;"
        ])
    }

    func testParseModule() throws {
        let pmod = try PackageModule(parse: "Foo:skip-model/SkipModel")
        XCTAssertEqual("Foo", pmod.moduleName)
        XCTAssertEqual(1, pmod.dependencies.count)
        XCTAssertEqual("skip-model", pmod.dependencies.first?.repositoryName)
        XCTAssertEqual("SkipModel", pmod.dependencies.first?.moduleName)
    }

    // MARK: - Meta Generate Tests

    func testGitRemoteToHTTPS() {
        XCTAssertEqual("https://github.com/Org/Repo", MetaIndexCommand.gitRemoteToHTTPS("https://github.com/Org/Repo.git"))
        XCTAssertEqual("https://github.com/Org/Repo", MetaIndexCommand.gitRemoteToHTTPS("git@github.com:Org/Repo.git"))
        XCTAssertEqual("https://github.com/Org/Repo", MetaIndexCommand.gitRemoteToHTTPS("https://github.com/Org/Repo"))
        XCTAssertEqual("https://gitlab.com/Org/Repo", MetaIndexCommand.gitRemoteToHTTPS("git@gitlab.com:Org/Repo.git"))
    }

    func testParseGitOriginURL() throws {
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try """
        [core]
        \trepositoryformatversion = 0
        \tfilemode = true
        [remote "origin"]
        \turl = https://github.com/Example/MyApp.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        """.write(to: tmpDir.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)

        let url = cmd.parseGitOriginURL(projectRoot: tmpDir)
        XCTAssertEqual(url, "https://github.com/Example/MyApp.git")
    }

    func testLocaleNormalization() {
        // Apple codes → BCP 47 canonical
        XCTAssertEqual("ar", MetaIndexCommand.normalizeLocale("ar-SA", convention: .apple))       // Arabic
        XCTAssertEqual("zh-Hans", MetaIndexCommand.normalizeLocale("zh-Hans", convention: .apple)) // Chinese Simplified
        XCTAssertEqual("zh-Hant", MetaIndexCommand.normalizeLocale("zh-Hant", convention: .apple)) // Chinese Traditional
        XCTAssertEqual("en", MetaIndexCommand.normalizeLocale("en-US", convention: .apple))        // English (US) → default English
        XCTAssertEqual("en-GB", MetaIndexCommand.normalizeLocale("en-GB", convention: .apple))     // English (UK) preserved
        XCTAssertEqual("en-AU", MetaIndexCommand.normalizeLocale("en-AU", convention: .apple))     // English (AU) preserved
        XCTAssertEqual("fr", MetaIndexCommand.normalizeLocale("fr-FR", convention: .apple))        // French (France) → French
        XCTAssertEqual("fr-CA", MetaIndexCommand.normalizeLocale("fr-CA", convention: .apple))     // French (Canada) preserved
        XCTAssertEqual("de", MetaIndexCommand.normalizeLocale("de-DE", convention: .apple))        // German
        XCTAssertEqual("es", MetaIndexCommand.normalizeLocale("es-ES", convention: .apple))        // Spanish (Spain) → Spanish
        XCTAssertEqual("es-MX", MetaIndexCommand.normalizeLocale("es-MX", convention: .apple))     // Spanish (Mexico) preserved
        XCTAssertEqual("nl", MetaIndexCommand.normalizeLocale("nl-NL", convention: .apple))        // Dutch
        XCTAssertEqual("pt-BR", MetaIndexCommand.normalizeLocale("pt-BR", convention: .apple))     // Portuguese (Brazil)
        XCTAssertEqual("pt", MetaIndexCommand.normalizeLocale("pt-PT", convention: .apple))        // Portuguese (Portugal) → Portuguese
        XCTAssertEqual("he", MetaIndexCommand.normalizeLocale("he", convention: .apple))           // Hebrew (Apple)
        XCTAssertEqual("ja", MetaIndexCommand.normalizeLocale("ja", convention: .apple))           // Japanese (Apple)
        XCTAssertEqual("ko", MetaIndexCommand.normalizeLocale("ko", convention: .apple))           // Korean (Apple)
        XCTAssertEqual("no", MetaIndexCommand.normalizeLocale("no", convention: .apple))           // Norwegian (Apple)

        // Google codes → BCP 47 canonical
        XCTAssertEqual("ar", MetaIndexCommand.normalizeLocale("ar", convention: .google))           // Arabic
        XCTAssertEqual("zh-Hans", MetaIndexCommand.normalizeLocale("zh-CN", convention: .google))   // Chinese Simplified
        XCTAssertEqual("zh-Hant", MetaIndexCommand.normalizeLocale("zh-TW", convention: .google))   // Chinese Traditional
        XCTAssertEqual("zh-Hant", MetaIndexCommand.normalizeLocale("zh-HK", convention: .google))   // Chinese Traditional (HK)
        XCTAssertEqual("he", MetaIndexCommand.normalizeLocale("iw-IL", convention: .google))        // Hebrew (legacy "iw")
        XCTAssertEqual("en", MetaIndexCommand.normalizeLocale("en-US", convention: .google))        // same for both platforms
        XCTAssertEqual("cs", MetaIndexCommand.normalizeLocale("cs-CZ", convention: .google))        // Czech
        XCTAssertEqual("da", MetaIndexCommand.normalizeLocale("da-DK", convention: .google))        // Danish
        XCTAssertEqual("fi", MetaIndexCommand.normalizeLocale("fi-FI", convention: .google))        // Finnish
        XCTAssertEqual("el", MetaIndexCommand.normalizeLocale("el-GR", convention: .google))        // Greek
        XCTAssertEqual("hi", MetaIndexCommand.normalizeLocale("hi-IN", convention: .google))        // Hindi
        XCTAssertEqual("hu", MetaIndexCommand.normalizeLocale("hu-HU", convention: .google))        // Hungarian
        XCTAssertEqual("it", MetaIndexCommand.normalizeLocale("it-IT", convention: .google))        // Italian
        XCTAssertEqual("ja", MetaIndexCommand.normalizeLocale("ja-JP", convention: .google))        // Japanese
        XCTAssertEqual("ko", MetaIndexCommand.normalizeLocale("ko-KR", convention: .google))        // Korean
        XCTAssertEqual("no", MetaIndexCommand.normalizeLocale("no-NO", convention: .google))        // Norwegian
        XCTAssertEqual("pl", MetaIndexCommand.normalizeLocale("pl-PL", convention: .google))        // Polish
        XCTAssertEqual("ru", MetaIndexCommand.normalizeLocale("ru-RU", convention: .google))        // Russian
        XCTAssertEqual("sv", MetaIndexCommand.normalizeLocale("sv-SE", convention: .google))        // Swedish
        XCTAssertEqual("tr", MetaIndexCommand.normalizeLocale("tr-TR", convention: .google))        // Turkish
        XCTAssertEqual("ms", MetaIndexCommand.normalizeLocale("ms-MY", convention: .google))        // Malay
        XCTAssertEqual("es-419", MetaIndexCommand.normalizeLocale("es-419", convention: .google))   // Spanish (LatAm) preserved
        XCTAssertEqual("es-US", MetaIndexCommand.normalizeLocale("es-US", convention: .google))     // Spanish (US) preserved

        // Already canonical codes pass through unchanged
        XCTAssertEqual("ca", MetaIndexCommand.normalizeLocale("ca", convention: .apple))
        XCTAssertEqual("hr", MetaIndexCommand.normalizeLocale("hr", convention: .apple))
        XCTAssertEqual("ro", MetaIndexCommand.normalizeLocale("ro", convention: .apple))
        XCTAssertEqual("sk", MetaIndexCommand.normalizeLocale("sk", convention: .apple))
        XCTAssertEqual("uk", MetaIndexCommand.normalizeLocale("uk", convention: .apple))
        XCTAssertEqual("vi", MetaIndexCommand.normalizeLocale("vi", convention: .apple))
        XCTAssertEqual("th", MetaIndexCommand.normalizeLocale("th", convention: .apple))
        XCTAssertEqual("hr", MetaIndexCommand.normalizeLocale("hr", convention: .google))
        XCTAssertEqual("ro", MetaIndexCommand.normalizeLocale("ro", convention: .google))
        XCTAssertEqual("sk", MetaIndexCommand.normalizeLocale("sk", convention: .google))
        XCTAssertEqual("uk", MetaIndexCommand.normalizeLocale("uk", convention: .google))
        XCTAssertEqual("vi", MetaIndexCommand.normalizeLocale("vi", convention: .google))
        XCTAssertEqual("th", MetaIndexCommand.normalizeLocale("th", convention: .google))
    }

    func testMetadataKeyNormalization() {
        XCTAssertEqual("description", MetaIndexCommand.normalizeMetadataKey("full_description", platform: .android))
        XCTAssertEqual("subtitle", MetaIndexCommand.normalizeMetadataKey("short_description", platform: .android))
        XCTAssertEqual("title", MetaIndexCommand.normalizeMetadataKey("title", platform: .android))
        XCTAssertEqual("releaseNotes", MetaIndexCommand.normalizeMetadataKey("release_notes", platform: .ios))
        XCTAssertEqual("privacyURL", MetaIndexCommand.normalizeMetadataKey("privacy_url", platform: .ios))
        XCTAssertEqual("supportURL", MetaIndexCommand.normalizeMetadataKey("support_url", platform: .ios))
        XCTAssertEqual("subtitle", MetaIndexCommand.normalizeMetadataKey("subtitle", platform: .ios))
    }

    func testParseSkipEnv() throws {
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let envFile = tmpDir.appendingPathComponent("Skip.env")
        try """
        PRODUCT_NAME = TestApp
        PRODUCT_BUNDLE_IDENTIFIER = com.example.test
        MARKETING_VERSION = 1.2.3
        CURRENT_PROJECT_VERSION = 42
        ANDROID_APPLICATION_ID = com.example.test.android
        APPLE_APP_STORE_ID = 123456789
        GOOGLE_PLAY_STORE_ID = com.example.test
        """.write(to: envFile, atomically: true, encoding: .utf8)

        let env = try cmd.parseSkipEnv(at: envFile)
        XCTAssertEqual(env["PRODUCT_NAME"], "TestApp")
        XCTAssertEqual(env["PRODUCT_BUNDLE_IDENTIFIER"], "com.example.test")
        XCTAssertEqual(env["MARKETING_VERSION"], "1.2.3")
        XCTAssertEqual(env["CURRENT_PROJECT_VERSION"], "42")
        XCTAssertEqual(env["ANDROID_APPLICATION_ID"], "com.example.test.android")
        XCTAssertEqual(env["APPLE_APP_STORE_ID"], "123456789")
        XCTAssertEqual(env["GOOGLE_PLAY_STORE_ID"], "com.example.test")
    }

    func testParseInfoPlist() throws {
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let plistFile = tmpDir.appendingPathComponent("Info.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ITSAppUsesNonExemptEncryption</key>
            <false/>
            <key>NSLocationWhenInUseUsageDescription</key>
            <string>We need your location for nearby search</string>
            <key>NSCameraUsageDescription</key>
            <string>We need camera access for photos</string>
        </dict>
        </plist>
        """.write(to: plistFile, atomically: true, encoding: .utf8)

        let info = try cmd.parseInfoPlist(at: plistFile)
        XCTAssertEqual(info["ITSAppUsesNonExemptEncryption"] as? Bool, false)

        // Without xcstrings: descriptions use the default locale
        let permissions = try cmd.extractIOSPermissions(at: plistFile, xcstringsURL: nil)
        XCTAssertEqual(permissions.count, 2)
        let permKeys = permissions.compactMap { $0["key"] as? String }.sorted()
        XCTAssertEqual(permKeys, ["NSCameraUsageDescription", "NSLocationWhenInUseUsageDescription"])
        let cameraDesc = permissions.first(where: { $0["key"] as? String == "NSCameraUsageDescription" })?["description"] as? [String: String]
        XCTAssertEqual(cameraDesc?["en"], "We need camera access for photos")

        // With xcstrings: translations are merged in
        let xcstringsFile = tmpDir.appendingPathComponent("InfoPlist.xcstrings")
        try """
        {
          "sourceLanguage" : "en",
          "strings" : {
            "NSCameraUsageDescription" : {
              "localizations" : {
                "fr" : {
                  "stringUnit" : {
                    "state" : "translated",
                    "value" : "Accès caméra pour les photos"
                  }
                },
                "zh-Hans" : {
                  "stringUnit" : {
                    "state" : "translated",
                    "value" : "需要相机权限来拍照"
                  }
                }
              }
            }
          },
          "version" : "1.0"
        }
        """.write(to: xcstringsFile, atomically: true, encoding: .utf8)

        let localizedPerms = try cmd.extractIOSPermissions(at: plistFile, xcstringsURL: xcstringsFile)
        let cameraPerm = localizedPerms.first(where: { $0["key"] as? String == "NSCameraUsageDescription" })
        let cameraDescs = cameraPerm?["description"] as? [String: String]
        XCTAssertEqual(cameraDescs?["en"], "We need camera access for photos")
        XCTAssertEqual(cameraDescs?["fr"], "Accès caméra pour les photos")
        XCTAssertEqual(cameraDescs?["zh-Hans"], "需要相机权限来拍照")  // zh-Hans is canonical BCP 47
    }

    func testParseAndroidManifest() throws {
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let manifestFile = tmpDir.appendingPathComponent("AndroidManifest.xml")
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            <!-- <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/> -->
            <uses-permission android:name="android.permission.INTERNET" />
            <uses-permission android:name="android.permission.CAMERA" />
            <application
                android:label="${PRODUCT_NAME}"
                android:name=".AndroidAppMain">
            </application>
        </manifest>
        """.write(to: manifestFile, atomically: true, encoding: .utf8)

        let permissions = try cmd.extractAndroidPermissions(at: manifestFile)
        // Should only include non-commented permissions
        XCTAssertEqual(permissions.count, 2)
        XCTAssertEqual(permissions[0]["key"], "android.permission.INTERNET")
        XCTAssertEqual(permissions[1]["key"], "android.permission.CAMERA")

        let meta = try cmd.parseAndroidManifest(at: manifestFile)
        XCTAssertEqual(meta["label"] as? String, "${PRODUCT_NAME}")
    }

    func testParseFastlaneMetadata() throws {
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create Android-style metadata structure
        let metaDir = tmpDir.appendingPathComponent("metadata/android")
        let enDir = metaDir.appendingPathComponent("en-US")
        let frDir = metaDir.appendingPathComponent("fr-FR")
        let zhDir = metaDir.appendingPathComponent("zh-Hans")
        try FileManager.default.createDirectory(at: enDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: frDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zhDir, withIntermediateDirectories: true)

        try "My App".write(to: enDir.appendingPathComponent("title.txt"), atomically: true, encoding: .utf8)
        try "A great app".write(to: enDir.appendingPathComponent("full_description.txt"), atomically: true, encoding: .utf8)
        try "Great".write(to: enDir.appendingPathComponent("short_description.txt"), atomically: true, encoding: .utf8)

        try "Mon App".write(to: frDir.appendingPathComponent("title.txt"), atomically: true, encoding: .utf8)
        try "Une super app".write(to: frDir.appendingPathComponent("full_description.txt"), atomically: true, encoding: .utf8)

        try "My App Chinese".write(to: zhDir.appendingPathComponent("title.txt"), atomically: true, encoding: .utf8)

        let result = cmd.parseFastlaneMetadata(folder: metaDir, platform: .android)

        // Check title across locales
        let titles = result["title"] as? [String: String]
        XCTAssertEqual(titles?["en"], "My App")
        XCTAssertEqual(titles?["fr"], "Mon App")
        // zh-Hans is the canonical BCP 47 code for Simplified Chinese
        XCTAssertEqual(titles?["zh-Hans"], "My App Chinese")

        // Check description (full_description → "description")
        let descs = result["description"] as? [String: String]
        XCTAssertEqual(descs?["en"], "A great app")
        XCTAssertEqual(descs?["fr"], "Une super app")

        // Check short description
        let subtitles = result["subtitle"] as? [String: String]
        XCTAssertEqual(subtitles?["en"], "Great")
    }

    func testParseEntitlements() throws {
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let entFile = tmpDir.appendingPathComponent("Entitlements.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.developer.aps-environment</key>
            <string>production</string>
            <key>com.apple.security.app-sandbox</key>
            <true/>
        </dict>
        </plist>
        """.write(to: entFile, atomically: true, encoding: .utf8)

        let entitlements = try cmd.parseEntitlements(at: entFile)
        XCTAssertEqual(entitlements["com.apple.developer.aps-environment"] as? String, "production")
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
    }

    func testMetaGenerateCatalogStructure() throws {
        // Test that a generated catalog from a mock project has the expected structure.
        // We can't call generateAppCatalog directly (needs parseSwiftPackage), but we
        // can test that building iOS/Android metadata dictionaries produces correct output.
        let cmd = MetaIndexCommand()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a minimal app project structure
        let fm = FileManager.default
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Sources/TestApp/Skip"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Sources/TestApp/Resources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Tests/TestAppTests"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Darwin/Sources"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Darwin/TestApp.xcodeproj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Darwin/Assets.xcassets/AccentColor.colorset"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Darwin/Assets.xcassets/AppIcon.appiconset"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Darwin/fastlane/metadata/en-US"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Darwin/fastlane/metadata/fr-FR"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Android/app/src/main/kotlin"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Android/fastlane/metadata/android/en-US"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmpDir.appendingPathComponent("Android/gradle/wrapper"), withIntermediateDirectories: true)

        // Required files
        try "".write(to: tmpDir.appendingPathComponent("Sources/TestApp/Skip/skip.yml"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Sources/TestApp/Resources/Localizable.xcstrings"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Darwin/Sources/Main.swift"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Darwin/TestApp.xcconfig"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Darwin/TestApp.xcodeproj/project.pbxproj"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmpDir.appendingPathComponent("Darwin/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmpDir.appendingPathComponent("Darwin/Assets.xcassets/AccentColor.colorset/Contents.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: tmpDir.appendingPathComponent("Darwin/Assets.xcassets/AppIcon.appiconset/Contents.json"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Android/gradle.properties"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Android/settings.gradle.kts"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Android/app/build.gradle.kts"), atomically: true, encoding: .utf8)
        try "".write(to: tmpDir.appendingPathComponent("Android/app/proguard-rules.pro"), atomically: true, encoding: .utf8)

        // Skip.env
        try """
        PRODUCT_NAME = TestApp
        PRODUCT_BUNDLE_IDENTIFIER = com.example.testapp
        MARKETING_VERSION = 2.0.0
        CURRENT_PROJECT_VERSION = 10
        APPLE_APP_STORE_ID = 9876543
        GOOGLE_PLAY_STORE_ID = com.example.testapp
        """.write(to: tmpDir.appendingPathComponent("Skip.env"), atomically: true, encoding: .utf8)

        // Info.plist with a permission
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>ITSAppUsesNonExemptEncryption</key>
            <false/>
            <key>NSPhotoLibraryUsageDescription</key>
            <string>Access photos for sharing</string>
        </dict>
        </plist>
        """.write(to: tmpDir.appendingPathComponent("Darwin/Info.plist"), atomically: true, encoding: .utf8)

        // Entitlements
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>com.apple.developer.aps-environment</key>
            <string>development</string>
        </dict>
        </plist>
        """.write(to: tmpDir.appendingPathComponent("Darwin/Entitlements.plist"), atomically: true, encoding: .utf8)

        // AndroidManifest.xml
        try """
        <?xml version="1.0" encoding="utf-8"?>
        <manifest xmlns:android="http://schemas.android.com/apk/res/android">
            <uses-permission android:name="android.permission.INTERNET" />
            <uses-permission android:name="android.permission.CAMERA" />
            <application android:label="${PRODUCT_NAME}" android:name=".AndroidAppMain">
            </application>
        </manifest>
        """.write(to: tmpDir.appendingPathComponent("Android/app/src/main/AndroidManifest.xml"), atomically: true, encoding: .utf8)

        // iOS fastlane metadata
        try "TestApp".write(to: tmpDir.appendingPathComponent("Darwin/fastlane/metadata/en-US/title.txt"), atomically: true, encoding: .utf8)
        try "A test app".write(to: tmpDir.appendingPathComponent("Darwin/fastlane/metadata/en-US/description.txt"), atomically: true, encoding: .utf8)
        try "TestApp FR".write(to: tmpDir.appendingPathComponent("Darwin/fastlane/metadata/fr-FR/title.txt"), atomically: true, encoding: .utf8)

        // Android fastlane metadata
        try "TestApp".write(to: tmpDir.appendingPathComponent("Android/fastlane/metadata/android/en-US/title.txt"), atomically: true, encoding: .utf8)
        try "A test app for Android".write(to: tmpDir.appendingPathComponent("Android/fastlane/metadata/android/en-US/full_description.txt"), atomically: true, encoding: .utf8)

        // Build the project layout (with no URL checks since this is a test)
        let appProject = AppProjectLayout(moduleName: "TestApp", root: tmpDir, check: AppProjectLayout.noURLChecks)
        let env = try cmd.parseSkipEnv(at: appProject.skipEnv)

        // Build iOS metadata
        let ios = try cmd.buildIOSMetadata(appProject: appProject, projectRoot: tmpDir, productName: env["PRODUCT_NAME"]!, bundleId: env["PRODUCT_BUNDLE_IDENTIFIER"]!, version: env["MARKETING_VERSION"]!, buildNumber: env["CURRENT_PROJECT_VERSION"]!, appleStoreId: env["APPLE_APP_STORE_ID"])

        XCTAssertEqual(ios["bundleIdentifier"] as? String, "com.example.testapp")
        XCTAssertEqual(ios["version"] as? String, "2.0.0")
        let iosChannels = ios["channels"] as? [String: Any]
        let appleAppStore = iosChannels?["appleappstore"] as? [String: Any]
        XCTAssertEqual(appleAppStore?["id"] as? String, "9876543")
        XCTAssertEqual(appleAppStore?["url"] as? String, "https://apps.apple.com/app/id9876543")

        // Check iOS permissions
        let iosPerms = ios["permissions"] as? [[String: Any]]
        XCTAssertEqual(iosPerms?.count, 1)
        XCTAssertEqual(iosPerms?.first?["key"] as? String, "NSPhotoLibraryUsageDescription")
        let photoDesc = iosPerms?.first?["description"] as? [String: String]
        XCTAssertEqual(photoDesc?["en"], "Access photos for sharing")

        // Check iOS metadata (entitlements are now inside metadata dict)
        let iosMetadata = ios["metadata"] as? [String: Any]
        let entitlements = iosMetadata?["entitlements"] as? [String: Any]
        XCTAssertEqual(entitlements?["com.apple.developer.aps-environment"] as? String, "development")

        // Check iOS localized metadata
        let iosTitle = ios["title"] as? [String: String]
        XCTAssertEqual(iosTitle?["en"], "TestApp")
        XCTAssertEqual(iosTitle?["fr"], "TestApp FR")

        // Build Android metadata
        let android = try cmd.buildAndroidMetadata(appProject: appProject, projectRoot: tmpDir, productName: env["PRODUCT_NAME"]!, bundleId: env["PRODUCT_BUNDLE_IDENTIFIER"]!, androidAppId: nil, version: env["MARKETING_VERSION"]!, buildNumber: env["CURRENT_PROJECT_VERSION"]!, googlePlayStoreId: env["GOOGLE_PLAY_STORE_ID"])

        XCTAssertEqual(android["applicationId"] as? String, "com.example.testapp")
        let androidChannels = android["channels"] as? [String: Any]
        let googlePlayStore = androidChannels?["googleplaystore"] as? [String: Any]
        XCTAssertEqual(googlePlayStore?["id"] as? String, "com.example.testapp")
        XCTAssertEqual(googlePlayStore?["url"] as? String, "https://play.google.com/store/apps/details?id=com.example.testapp")

        // Check Android permissions
        let androidPerms = android["permissions"] as? [[String: String]]
        XCTAssertEqual(androidPerms?.count, 2)
        XCTAssertEqual(androidPerms?[0]["key"], "android.permission.INTERNET")
        XCTAssertEqual(androidPerms?[1]["key"], "android.permission.CAMERA")

        // Check Android localized metadata
        let androidTitle = android["title"] as? [String: String]
        XCTAssertEqual(androidTitle?["en"], "TestApp")
        let androidDesc = android["description"] as? [String: String]
        XCTAssertEqual(androidDesc?["en"], "A test app for Android")
    }

    func testPNGDimensionParsing() {
        // Construct a minimal valid PNG: 8-byte signature + IHDR chunk
        // IHDR: 4-byte length (13) + "IHDR" + 4-byte width + 4-byte height + 5 bytes (bit depth, color type, etc.)
        var png = Data()
        // PNG signature
        png.append(contentsOf: [137, 80, 78, 71, 13, 10, 26, 10] as [UInt8])
        // IHDR chunk length: 13 bytes
        png.append(contentsOf: [0, 0, 0, 13] as [UInt8])
        // IHDR type
        png.append(contentsOf: [73, 72, 68, 82] as [UInt8]) // "IHDR"
        // Width: 320 (0x00000140)
        png.append(contentsOf: [0, 0, 1, 64] as [UInt8])
        // Height: 480 (0x000001E0)
        png.append(contentsOf: [0, 0, 1, 224] as [UInt8])
        // bit depth, color type, compression, filter, interlace
        png.append(contentsOf: [8, 6, 0, 0, 0] as [UInt8])

        let (width, height) = ImageResourceRef.parsePNGDimensions(png)
        XCTAssertEqual(width, 320)
        XCTAssertEqual(height, 480)

        // Invalid data should return (0, 0)
        let (w2, h2) = ImageResourceRef.parsePNGDimensions(Data([0, 1, 2]))
        XCTAssertEqual(w2, 0)
        XCTAssertEqual(h2, 0)
    }

    func testImageResourceRefFromPNG() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a minimal PNG file
        var png = Data()
        png.append(contentsOf: [137, 80, 78, 71, 13, 10, 26, 10] as [UInt8])
        png.append(contentsOf: [0, 0, 0, 13] as [UInt8])
        png.append(contentsOf: [73, 72, 68, 82] as [UInt8])
        png.append(contentsOf: [0, 0, 4, 0] as [UInt8])   // 1024
        png.append(contentsOf: [0, 0, 4, 0] as [UInt8])   // 1024
        png.append(contentsOf: [8, 6, 0, 0, 0] as [UInt8])

        let iconFile = tmpDir.appendingPathComponent("icon.png")
        try png.write(to: iconFile)

        let ref = try XCTUnwrap(ImageResourceRef.from(pngURL: iconFile, relativeTo: tmpDir))
        XCTAssertEqual(ref.width, 1024)
        XCTAssertEqual(ref.height, 1024)
        XCTAssertEqual(ref.location, "icon.png")
        XCTAssertEqual(ref.mimeType, "image/png")
        XCTAssertEqual(ref.size, Int64(png.count))
        XCTAssertEqual(ref.digest, "sha256:8e20268c0d22111a27852d29c38e49bf908ff15b2380eb24c0675b2f500ba1e6")
    }

    func testParseSwiftToolchainAPI() async throws {
        let staticLinuxSDKs = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: "static")
        let staticDownloadURL = "https://download.swift.org/swift-6.2.3-release/static-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_static-linux-0.0.1.artifactbundle.tar.gz"
        XCTAssertTrue(staticLinuxSDKs.contains(where: { $0.downloadURL.absoluteString == staticDownloadURL }), "missing expected path in: \(staticLinuxSDKs)")

        let wasmSDKs = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: "wasm")
        let wasmDownloadURL = "https://download.swift.org/swift-6.2.3-release/wasm-sdk/swift-6.2.3-RELEASE/swift-6.2.3-RELEASE_wasm.artifactbundle.tar.gz"
        XCTAssertTrue(wasmSDKs.contains(where: { $0.downloadURL.absoluteString == wasmDownloadURL }), "missing expected path in: \(wasmSDKs)")

        let wasmDevSDKs = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: "wasm", forDevelVersion: "6.2")
        let wasmDevDownloadURL = "https://download.swift.org/swift-6.2-branch/wasm-sdk/swift-6.2-DEVELOPMENT-SNAPSHOT-2025-12-03-a/swift-6.2-DEVELOPMENT-SNAPSHOT-2025-12-03-a_wasm.artifactbundle.tar.gz"
        XCTAssertTrue(wasmDevSDKs.contains(where: { $0.downloadURL.absoluteString == wasmDevDownloadURL }), "missing expected path in: \(wasmDevSDKs)")

        let androidDevelopmentDownloadURL = "https://download.swift.org/development/android-sdk/swift-DEVELOPMENT-SNAPSHOT-2025-12-17-a/swift-DEVELOPMENT-SNAPSHOT-2025-12-17-a_android.artifactbundle.tar.gz"
        let androidDevSDKs = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: "android", forDevelVersion: "main")
        XCTAssertTrue(androidDevSDKs.contains(where: { $0.downloadURL.absoluteString == androidDevelopmentDownloadURL }), "missing expected path in: \(androidDevSDKs)")

        let androidDev63DownloadURL = "https://download.swift.org/swift-6.3-branch/android-sdk/swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a/swift-6.3-DEVELOPMENT-SNAPSHOT-2025-12-18-a_android.artifactbundle.tar.gz"
        let androidDev63SDKs = try await SwiftSDKOpenAPI.fetchSDKs(sdkName: "android", forDevelVersion: "6.3")
        XCTAssertTrue(androidDev63SDKs.contains(where: { $0.downloadURL.absoluteString == androidDev63DownloadURL }), "missing expected path in: \(androidDev63SDKs)")
    }

    // MARK: - iOS AppIcon Discovery

    func testFilenameLooksLikeMacIcon() {
        // legacy "~mac" idiom suffix and explicit macOS markers
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon~mac.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon-mac.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon-mac-1024.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon-mac@2x.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("appicon-mac-1024x1024@2x.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon-macOS.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("appicon-macos-1024.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon_mac_512.png"))

        // genuine iOS icon filenames must NOT be classified as macOS
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon~ios-marketing.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon~ipad.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon-83.5@2x~ipad.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon-20@2x.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("AppIcon@3x.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("appicon-ios-marketing-1024x1024@1x.png"))
        // false-positive guard: bare substring "mac" should not match
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("imacolor.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeMacIcon("macaron.png"))
    }

    func testFilenameLooksLikeIOSMarketingIcon() {
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeIOSMarketingIcon("AppIcon~ios-marketing.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeIOSMarketingIcon("appicon-ios-marketing-1024x1024@1x.png"))
        XCTAssertTrue(MetaIndexCommand.filenameLooksLikeIOSMarketingIcon("AppIcon-iOS-Marketing.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeIOSMarketingIcon("AppIcon-20@2x.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeIOSMarketingIcon("AppIcon~ipad.png"))
        XCTAssertFalse(MetaIndexCommand.filenameLooksLikeIOSMarketingIcon("AppIcon-mac-1024.png"))
    }

    func testParseAssetSizeField() {
        XCTAssertEqual(1024, MetaIndexCommand.parseAssetSizeField("1024x1024"))
        XCTAssertEqual(60, MetaIndexCommand.parseAssetSizeField("60x60"))
        XCTAssertEqual(83, MetaIndexCommand.parseAssetSizeField("83.5x83.5")) // truncates decimals
        XCTAssertEqual(0, MetaIndexCommand.parseAssetSizeField(nil))
        XCTAssertEqual(0, MetaIndexCommand.parseAssetSizeField(""))
        XCTAssertEqual(0, MetaIndexCommand.parseAssetSizeField("garbage"))
    }

    func testFindIOSAppIconPrefersMarketingFromContentsJSON() throws {
        let tmp = try makeAppIconSet(named: "PreferMarketing")
        defer { try? FileManager.default.removeItem(at: tmp.root) }

        // Multiple iOS entries; the marketing one is NOT the largest by file size,
        // but should still be picked because its idiom is "ios-marketing".
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon-60@3x.png"), width: 180, height: 180, padBytes: 10_000)
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon~ios-marketing.png"), width: 1024, height: 1024, padBytes: 1_000)
        try writeContents(folder: tmp.folder, images: [
            ["filename": "AppIcon-60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60"],
            ["filename": "AppIcon~ios-marketing.png", "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024"],
        ])

        let cmd = MetaIndexCommand()
        let ref = try XCTUnwrap(cmd.findIOSAppIcon(in: tmp.folder, relativeTo: tmp.root))
        XCTAssertEqual(1024, ref.width)
        XCTAssertEqual(1024, ref.height)
        XCTAssertTrue(ref.location.hasSuffix("AppIcon~ios-marketing.png"), "got: \(ref.location)")
    }

    func testFindIOSAppIconExcludesMacEntryEvenWhenLarger() throws {
        let tmp = try makeAppIconSet(named: "ExcludeMacIdiom")
        defer { try? FileManager.default.removeItem(at: tmp.root) }

        // A macOS-idiom 1024 entry is larger than the iOS 60×60 entry, but must be
        // excluded — Contents.json marks it as macOS-only.
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon-mac-1024.png"), width: 1024, height: 1024, padBytes: 50_000)
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon-60@3x.png"), width: 180, height: 180, padBytes: 500)
        try writeContents(folder: tmp.folder, images: [
            ["filename": "AppIcon-mac-1024.png", "idiom": "mac", "scale": "1x", "size": "1024x1024"],
            ["filename": "AppIcon-60@3x.png", "idiom": "iphone", "scale": "3x", "size": "60x60"],
        ])

        let cmd = MetaIndexCommand()
        let ref = try XCTUnwrap(cmd.findIOSAppIcon(in: tmp.folder, relativeTo: tmp.root))
        XCTAssertEqual(180, ref.width)
        XCTAssertTrue(ref.location.hasSuffix("AppIcon-60@3x.png"), "got: \(ref.location)")
    }

    func testFindIOSAppIconFallbackPrefersMarketingByFilename() throws {
        let tmp = try makeAppIconSet(named: "FallbackByFilename")
        defer { try? FileManager.default.removeItem(at: tmp.root) }

        // No Contents.json — we should still prefer the file whose name identifies
        // it as the iOS marketing icon over a larger non-marketing PNG.
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon-60@3x.png"), width: 180, height: 180, padBytes: 50_000)
        try writeFakePNG(tmp.folder.appendingPathComponent("appicon-ios-marketing-1024x1024@1x.png"), width: 1024, height: 1024, padBytes: 1_000)

        let cmd = MetaIndexCommand()
        let ref = try XCTUnwrap(cmd.findIOSAppIcon(in: tmp.folder, relativeTo: tmp.root))
        XCTAssertTrue(ref.location.hasSuffix("appicon-ios-marketing-1024x1024@1x.png"), "got: \(ref.location)")
    }

    func testFindIOSAppIconFallbackExcludesMacFilenames() throws {
        let tmp = try makeAppIconSet(named: "FallbackExcludesMac")
        defer { try? FileManager.default.removeItem(at: tmp.root) }

        // No Contents.json. A macOS-style filename is the largest PNG on disk; the
        // selection must skip it and fall back to the next-largest non-mac PNG.
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon-mac-1024.png"), width: 1024, height: 1024, padBytes: 50_000)
        try writeFakePNG(tmp.folder.appendingPathComponent("AppIcon-60@3x.png"), width: 180, height: 180, padBytes: 500)

        let cmd = MetaIndexCommand()
        let ref = try XCTUnwrap(cmd.findIOSAppIcon(in: tmp.folder, relativeTo: tmp.root))
        XCTAssertTrue(ref.location.hasSuffix("AppIcon-60@3x.png"), "got: \(ref.location)")
    }

    func testFindIOSAppIconReturnsNilForEmptyOrMissingFolder() {
        let cmd = MetaIndexCommand()
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        XCTAssertNil(cmd.findIOSAppIcon(in: missing, relativeTo: missing))
    }

    // MARK: - Helpers for AppIcon discovery tests

    private struct TmpAppIconSet { let root: URL; let folder: URL }

    private func makeAppIconSet(named name: String) throws -> TmpAppIconSet {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(name)-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return TmpAppIconSet(root: root, folder: folder)
    }

    private func writeContents(folder: URL, images: [[String: String]]) throws {
        let payload: [String: Any] = ["images": images, "info": ["version": 1, "author": "test"]]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        try data.write(to: folder.appendingPathComponent("Contents.json"))
    }

    /// Write a minimal PNG-shaped file with the given IHDR width/height and optional
    /// padding bytes (used to make file-size comparisons meaningful in tests).
    private func writeFakePNG(_ url: URL, width: Int, height: Int, padBytes: Int) throws {
        var data = Data([137, 80, 78, 71, 13, 10, 26, 10]) // PNG signature
        data.append(contentsOf: [0, 0, 0, 13])             // IHDR length = 13
        data.append(contentsOf: [0x49, 0x48, 0x44, 0x52])  // "IHDR"
        // width (big-endian)
        data.append(UInt8((width >> 24) & 0xFF))
        data.append(UInt8((width >> 16) & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))
        // height (big-endian)
        data.append(UInt8((height >> 24) & 0xFF))
        data.append(UInt8((height >> 16) & 0xFF))
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))
        // bit_depth, color_type, compression, filter, interlace + 4 byte CRC placeholder
        data.append(contentsOf: [8, 6, 0, 0, 0, 0, 0, 0, 0])
        if padBytes > 0 {
            data.append(contentsOf: [UInt8](repeating: 0, count: padBytes))
        }
        try data.write(to: url)
    }
}

