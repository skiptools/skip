#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class NumberFormatterTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "NumberFormatterTests")

    func testNumberFormatter() throws {
        logger.debug("testing NumberFormatter")
//        let ob = NumberFormatter()
//        XCTAssertNotNil(ob)
    }
}
