#if !SKIP
@testable import SkipDemoApp
import SkipTest
#endif
import SkipDemoLib
import SkipFoundation
import SkipUI

final class SkipDemoAppTests: XCTestCase {
    func testSkipDemoApp() throws {
        XCTAssertEqual(3, 1 + 2 + 0)
        XCTAssertEqual("SkipDemoApp", SkipDemoAppInternalModuleName())
        XCTAssertEqual("SkipDemoApp", SkipDemoAppPublicModuleName())
        XCTAssertEqual("SkipDemoLib", SkipDemoLibPublicModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())
        XCTAssertEqual("SkipUI", SkipUIPublicModuleName())
    }
}
