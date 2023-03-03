#if !SKIP
@testable import SampleLib
import XCTest
#endif
import CrossFoundation

final class SampleLibTests: XCTestCase {
    func testSampleLib() throws {
        XCTAssertEqual(3.0 + 1.5, 9.0/2)
        XCTAssertEqual("SampleLib", SampleLibInternalModuleName())
        XCTAssertEqual("SampleLib", SampleLibPublicModuleName())
        XCTAssertEqual("CrossFoundation", CrossFoundationPublicModuleName())
    }
}
