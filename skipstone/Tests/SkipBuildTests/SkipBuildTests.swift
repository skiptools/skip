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
}

