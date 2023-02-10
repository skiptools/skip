#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class DateFormatterTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "DateFormatterTests")

    func testDateFormatter() throws {
        logger.debug("testing DateFormatter")
//        let ob = DateFormatter()
//        XCTAssertNotNil(ob)
    }
}
