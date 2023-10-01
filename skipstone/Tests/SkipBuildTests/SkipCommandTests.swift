import XCTest
@testable import SkipBuild
import TSCBasic

final class SkipCommandTests: XCTestCase {
    func testSkipVersion() async throws {
        try await XCTAssertEqualAsync(skipVersion.json(), skipstone("version", "-j").json()["version"])
    }
}


/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
