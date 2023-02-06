#if !SKIP
@testable import SkipFoundation
import SkipTest
#endif

final class SkipFoundationTests: SkipTestCase {
    #if !SKIP
    /// The modules that should be transpiled and tested
    override var targets: SkipTargetSet? { SkipTargetSet(.lib("SkipFoundation")) }

    public func testTranspiledTests() async throws {
        try await runGradleTests()
    }
    #endif

    func testSkipFoundation() throws {
        XCTAssertEqual(3, 1 + 2)
        XCTAssertEqual("SkipFoundation", SkipFoundationInternalModuleName())
        XCTAssertEqual("SkipFoundation", SkipFoundationPublicModuleName())
    }
}
