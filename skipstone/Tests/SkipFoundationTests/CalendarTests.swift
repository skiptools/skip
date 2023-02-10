#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class CalendarTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "CalendarTests")

    func testCalendar() throws {
        logger.debug("testing Calendar")
//        let ob = Calendar()
//        XCTAssertNotNil(ob)
    }
}
