#if !SKIP
@testable import SampleApp
import XCTest
#endif
import SampleLib
import CrossFoundation
import CrossUI

final class SampleAppTests: XCTestCase {
    func testSampleApp() throws {
        XCTAssertEqual(3, 1 + 2 + 0)
//        XCTAssertEqual("SampleApp", SampleAppInternalModuleName())
//        XCTAssertEqual("SampleApp", SampleAppPublicModuleName())
        XCTAssertEqual("SampleLib", SampleLibPublicModuleName())
        XCTAssertEqual("CrossFoundation", CrossFoundationPublicModuleName())
        XCTAssertEqual("CrossUI", CrossUIPublicModuleName())
    }
}
