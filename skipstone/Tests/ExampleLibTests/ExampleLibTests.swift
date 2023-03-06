#if !SKIP
@testable import ExampleLib
import XCTest
#endif
import CrossFoundation

final class ExampleLibTests: XCTestCase {
    func testExampleLib() throws {
        XCTAssertEqual(3.0 + 1.5, 9.0/2)
        XCTAssertEqual("ExampleLib", ExampleLibInternalModuleName())
        XCTAssertEqual("ExampleLib", ExampleLibPublicModuleName())
        XCTAssertEqual("CrossFoundation", CrossFoundationPublicModuleName())
    }
}
