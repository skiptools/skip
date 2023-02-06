#if !SKIP
@testable import SkipFoundation
import SkipTest
#endif

/// This test case will perform run the transpilation tests
final class TranspiledTests: SkipTranspilerTestCase {
    #if !SKIP
    /// The modules that should be transpiled and tested
    override var targets: SkipTargetSet? { SkipTargetSet(.lib("SkipFoundation")) }

    public func testTranspiledTests() async throws {
        try await runGradleTests()
    }
    #else
    public func testEmptyTest() {
        // need at least one test case or else: org.junit.runners.model.InvalidTestClassError
    }
    #endif
}
