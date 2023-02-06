#if !SKIP
@testable import SkipUI
import SkipTest
#endif
import SkipFoundation

final class SkipUITests: SkipTestCase {
    #if !SKIP
    /// The modules that should be transpiled and tested
    override var targets: SkipTargetSet? {
        SkipTargetSet(.app("SkipUI"), dependencies: [SkipTargetSet(.app("SkipFoundation"))])
    }

    public func testTranspiledTests() async throws {
        try await runGradleTests()
    }
    #endif
    
    func testSkipUI() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipUI", SkipUIInternalModuleName())
        XCTAssertEqual("SkipUI", SkipUIPublicModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())

    }
}
