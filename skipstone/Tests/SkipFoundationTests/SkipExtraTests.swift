#if !SKIP
@testable import SkipFoundation
import SkipTest
#endif

final class SkipExraTests: XCTestCase {
    func testSkipExtraTest() throws {
        XCTAssertEqual(3, 1*3)
    }
}
