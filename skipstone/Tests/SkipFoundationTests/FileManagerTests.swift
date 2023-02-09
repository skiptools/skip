#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class FileManagerTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "FileManagerTests")

    func testFileManager() throws {
        logger.log("temporary folder: \(NSTemporaryDirectory())")
        let fm = FileManager.default
    }
}
