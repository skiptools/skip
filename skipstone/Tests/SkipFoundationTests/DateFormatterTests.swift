#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class DateFormatterTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "DateFormatterTests")

    func testDateFormat() throws {
        let format = DateFormatter.dateFormat(fromTemplate: "MMM", options: 0, locale: Locale(identifier: "fr_FR"))
    }
}
