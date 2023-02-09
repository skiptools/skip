#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class FileManagerTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "FileManagerTests")

    func testFileManager() throws {
        let tmp = NSTemporaryDirectory()
        logger.log("temporary folder: \(tmp)")
        XCTAssertNotNil(tmp)
        XCTAssertNotEqual("", tmp)

        let fm = FileManager.default
        XCTAssertNotNil(fm)
    }
}
