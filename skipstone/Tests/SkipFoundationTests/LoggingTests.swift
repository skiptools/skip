#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class LoggingTests: XCTestCase {
    func testLogging() throws {
        let logger = Logger(subsystem: "SUBSYSTEM", category: "CATEGORY")
        logger.debug("debug message")
        logger.trace("trace message")
        logger.notice("notice message")
        logger.info("notice message")
        logger.warning("info message")
        logger.error("error message")
        logger.critical("critical message")
        logger.fault("fault message")

        logger.log(level: OSLogType.default, "default message")
        logger.log(level: OSLogType.debug, "debug message")
        logger.log(level: OSLogType.info, "notice message")
        logger.log(level: OSLogType.error, "error message")
        logger.log(level: OSLogType.fault, "fault message")
    }
}
