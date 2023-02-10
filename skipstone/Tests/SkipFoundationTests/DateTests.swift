#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class DateTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "DateTests")

    func testDateTime() throws {
        let date: Date = Date()
        XCTAssertNotEqual(0, date.getTime())
    }

    func testMultipleConstructorsSameParams() throws {
        let d1 = Date(timeIntervalSince1970: 99999.0)
        let d2 = Date(timeIntervalSinceReferenceDate: 99999.0)

        XCTAssertEqual(99999.0, d1.timeIntervalSince1970)
        XCTAssertEqual(978407199.0, d2.timeIntervalSince1970)

        XCTAssertEqual(-978207201.0, d1.timeIntervalSinceReferenceDate)
        XCTAssertEqual(99999.0, d2.timeIntervalSinceReferenceDate)
    }

    func testISOFormatting() throws {
        let d = Date.create(timeIntervalSince1970: 172348932.0)
        XCTAssertEqual(172348932.0, d.getTime())
        logger.info("date: \(d.ISO8601Format())")
        XCTAssertEqual("1975-06-18T18:42:12Z", d.ISO8601Format())

        let d2 = Date.create(timeIntervalSince1970: 999999999.0)
        XCTAssertEqual(999999999.0, d2.getTime())
        logger.info("date: \(d2.ISO8601Format())")
        XCTAssertEqual("2001-09-09T01:46:39Z", d2.ISO8601Format())

        let d3030 = Date.create(timeIntervalSince1970: 33450382800.0 - (5 * 60 * 60))
        XCTAssertEqual(33450382800.0 - (5 * 60 * 60), d3030.getTime())
        logger.info("date: \(d3030.ISO8601Format())")
        XCTAssertEqual("3030-01-01T00:00:00Z", d3030.ISO8601Format())

        XCTAssertEqual(-62135769600.0, Date.distantPast.getTime())
        XCTAssertEqual("0001-01-01T00:00:00Z", Date.distantPast.ISO8601Format())

        XCTAssertEqual(64092211200.0, Date.distantFuture.getTime())
        XCTAssertEqual("4001-01-01T00:00:00Z", Date.distantFuture.ISO8601Format())
    }

    func testAbsoluteTimeGetCurrent() {
        XCTAssertNotEqual(0, CFAbsoluteTimeGetCurrent())
    }
}
