#if !SKIP
@testable import CrossUI
import XCTest
#endif
import CrossFoundation

final class CrossUITests: XCTestCase {
    func testCrossUI() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("CrossUI", CrossUIInternalModuleName())
        XCTAssertEqual("CrossUI", CrossUIPublicModuleName())
        XCTAssertEqual("CrossFoundation", CrossFoundationPublicModuleName())
    }
}
