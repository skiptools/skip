#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class UUIDTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "UUIDTests")

    func testUUID() throws {
        XCTAssertNotEqual(UUID(), UUID())
        XCTAssertNotEqual("", UUID().uuidString)
        
        logger.log("UUID: \(UUID().uuidString)")

        let uuid: UUID = UUID.fromUUIDString(uuid: "d500d1f7-ddb0-439b-ab90-22fdbe5b5790")
        XCTAssertEqual("D500D1F7-DDB0-439B-AB90-22FDBE5B5790", uuid.uuidString)
    }
}
