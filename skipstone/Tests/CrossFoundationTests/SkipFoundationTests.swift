#if !SKIP
@testable import CrossFoundation
import XCTest
#endif

final class CrossFoundationTests: XCTestCase {
    func testCrossFoundation() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("CrossFoundation", CrossFoundationInternalModuleName())
        XCTAssertEqual("CrossFoundation", CrossFoundationPublicModuleName())

        #if SKIP
        XCTAssertEqual("Kotlin", foundationHelperDemo())
        #else
        XCTAssertEqual("Swift", foundationHelperDemo())
        #endif
    }

    // MARK: - ArrayTests

    func testArrayLiteralInit() {
        let emptyArray: [Int] = []
        XCTAssertEqual(emptyArray.count, 0)

        let singleElementArray = [1]
        XCTAssertEqual(singleElementArray.count, 1)

        let multipleElementArray = [1, 2]
        XCTAssertEqual(multipleElementArray.count, 2)
    }
}
