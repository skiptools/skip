#if !SKIP
@testable import ExampleApp
import XCTest
#endif
import ExampleLib
import CrossFoundation
import CrossUI

final class ExampleAppTests: XCTestCase {
    func testExampleApp() throws {
        XCTAssertEqual(3, 1 + 2 + 0)
//        XCTAssertEqual("ExampleApp", ExampleAppInternalModuleName())
//        XCTAssertEqual("ExampleApp", ExampleAppPublicModuleName())
        XCTAssertEqual("ExampleLib", ExampleLibPublicModuleName())
        XCTAssertEqual("CrossFoundation", CrossFoundationPublicModuleName())
        XCTAssertEqual("CrossUI", CrossUIPublicModuleName())
    }
}
