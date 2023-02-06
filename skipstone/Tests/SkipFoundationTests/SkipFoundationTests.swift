#if !SKIP
@testable import SkipFoundation
import SkipTest
#endif

final class SkipFoundationTests: XCTestCase {
    func testSkipFoundation() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipFoundation", SkipFoundationInternalModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())

        #if SKIP
        XCTAssertEqual("Kotlin", foundationHelperDemo())
        #else
        XCTAssertEqual("Swift", foundationHelperDemo())
        #endif
    }
}
