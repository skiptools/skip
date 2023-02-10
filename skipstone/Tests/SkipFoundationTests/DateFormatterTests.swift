#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class DateFormatterTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "DateFormatterTests")

    func testDateFormat() throws {
//        let date = Date(timeIntervalSince1970: 987654321.0)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        XCTAssertEqual("MM/dd/yyyy", dateFormatter.dateFormat)

//        let formattedDate = dateFormatter.string(from: date)
//        XCTAssertEqual("04/19/2001", formattedDate)

    }
}
