#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class TimeZoneTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "TimeZoneTests")

    func testTimeZone() throws {
        logger.debug("testing TimeZone")
//        let ob = TimeZone()
//        XCTAssertNotNil(ob)
    }
}
