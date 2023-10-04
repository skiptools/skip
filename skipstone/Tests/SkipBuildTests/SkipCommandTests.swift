import XCTest
@testable import SkipBuild
import TSCBasic

final class SkipCommandTests: XCTestCase {
    func testVersionCommand() async throws {
        try await XCTAssertEqualAsync(skipVersion.json(), skipstone("version", "-j").json()["version"])
    }

    func testInfoCommand() async throws {
        _ = try await skipstone("info", "-jA").json()
    }

    func testDoctorCommand() async throws {
        // run skip doctor with JSON array output and make sure we can parse the result
        try await XCTAssertEqualAsync(["msg": "Skip Doctor"], skipstone("doctor", "-jA").json().array?.first)
    }

}


/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
