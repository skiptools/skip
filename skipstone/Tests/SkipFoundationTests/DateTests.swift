#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class DateTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "DataTests")

    func testDate() throws {
        let date: Date = Date()
        XCTAssertNotEqual(0, date.getTime())

         let d: Date = Date.create(timeIntervalSince1970: 72348932.0)
        XCTAssertEqual(72348932.0, d.getTime())
    }
}
