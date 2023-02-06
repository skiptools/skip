#if !SKIP
@testable import SkipDemoApp
import SkipTest
#endif
import SkipDemoLib
import SkipFoundation
import SkipUI

final class SkipDemoAppTests: SkipTestCase {
    #if !SKIP
    /// The modules that should be transpiled and tested
    override var targets: SkipTargetSet? {
        SkipTargetSet(.app("SkipDemoApp"), dependencies: [
            SkipTargetSet(.lib("SkipUI"), dependencies: [SkipTargetSet(.lib("SkipFoundation"))]),
            SkipTargetSet(.lib("SkipDemoLib"), dependencies: [SkipTargetSet(.lib("SkipFoundation"))]),
        ])
    }

    public func testTranspiledTests() async throws {
        try await runGradleTests()
    }
    #endif

    func testSkipDemoApp() throws {
        XCTAssertEqual(3, 1 + 2 + 0)
        XCTAssertEqual("SkipDemoApp", SkipDemoAppInternalModuleName())
        XCTAssertEqual("SkipDemoApp", SkipDemoAppPublicModuleName())
        XCTAssertEqual("SkipDemoLib", SkipDemoLibPublicModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())
        XCTAssertEqual("SkipUI", SkipUIPublicModuleName())
    }
}
