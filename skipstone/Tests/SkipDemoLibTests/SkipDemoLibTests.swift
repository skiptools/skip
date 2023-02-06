#if !SKIP
@testable import SkipDemoLib
import SkipTest
#endif
import SkipFoundation

final class SkipDemoLibTests: XCTestCase {
    func testSkipDemoLib() throws {
        XCTAssertEqual(3.0 + 1.5, 9.0/2)
        XCTAssertEqual("SkipDemoLib", SkipDemoLibInternalModuleName())
        XCTAssertEqual("SkipDemoLib", SkipDemoLibPublicModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())
    }
}
