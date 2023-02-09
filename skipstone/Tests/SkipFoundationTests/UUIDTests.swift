#if !SKIP
@testable import SkipFoundation
import XCTest
#endif

final class UUIDTests: XCTestCase {
    var logger = Logger(subsystem: "test", category: "UUIDTests")

    func testRandomUUID() throws {
        XCTAssertNotEqual(UUID(), UUID())
        XCTAssertNotEqual("", UUID().uuidString)
        
        logger.log("UUID: \(UUID().uuidString)")
    }

    func testFixedUUID() throws {
        let uuid: UUID = UUID.fromUUIDString(uuid: "d500d1f7-ddb0-439b-ab90-22fdbe5b5790")
        XCTAssertEqual("D500D1F7-DDB0-439B-AB90-22FDBE5B5790", uuid.uuidString)
    }

    func testUUIDFromBits() throws {
        XCTAssertEqual("00000000-0000-0000-0000-000000000000", UUID(mostSigBits: 0, leastSigBits: 0).uuidString)
        XCTAssertEqual("00000000-0000-0001-0000-000000000000", UUID(mostSigBits: 1, leastSigBits: 0).uuidString)
        XCTAssertEqual("00000000-0000-0000-0000-000000000001", UUID(mostSigBits: 0, leastSigBits: 1).uuidString)
        XCTAssertEqual("00000000-0000-0064-0000-000000000064", UUID(mostSigBits: 100, leastSigBits: 100).uuidString)
        XCTAssertEqual("112210F4-7DE9-8115-0DB4-DA5F49F8B478", UUID(mostSigBits: 1234567890123456789, leastSigBits: 987654321098765432).uuidString)
        XCTAssertEqual("00000000-0005-3D9D-0000-000151280C98", UUID(mostSigBits: 343453, leastSigBits: 5656546456).uuidString)
    }
}
