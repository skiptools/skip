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
        let tmpFile = URL(fileURLWithPath: NSTemporaryDirectory().appending("/" + UUID().uuidString))
        try "Hello World".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }
        XCTAssertEqual("a591a6d40bf420404a011733cfb7b190d62c65bf0bcda32b57b277d9ad9f146e", try tmpFile.SHA256Hash())
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

    func testCreatePNG() throws {
        for size in [10, 100, 1024] {
            let _ = createSolidColorPNG(width: size, height: size, hexString: "4994EC") // ?.write(to: URL(fileURLWithPath: "/\(NSTemporaryDirectory())/img_\(size).png"))
        }
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
}
