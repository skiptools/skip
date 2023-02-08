#if !SKIP
@testable import SkipKotlin
import SkipUnit
#endif

final class SkipKotlinTests: XCTestCase {
    func testSkipKotlin() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipKotlin", SkipKotlinInternalModuleName())
        XCTAssertEqual("SkipKotlin", SkipKotlinPublicModuleName())
    }
}
