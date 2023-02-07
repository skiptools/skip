#if !SKIP
@testable import SkipFoundation
import SkipUnit
#endif

/// This test case will perform run the transpilation tests
final class TranspiledTests: SkipTranspilerTestCase {
    #if !SKIP
    public func testTranspiledTests() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.app("SkipDemoApp"), dependencies: [
            SkipTargetSet(.lib("SkipUI"), dependencies: [SkipTargetSet(.lib("SkipFoundation"))]),
            SkipTargetSet(.lib("SkipDemoLib"), dependencies: [SkipTargetSet(.lib("SkipFoundation"))]),
        ]))
    }
    #else
    public func testEmptyTest() {
        // need at least one test case or else: org.junit.runners.model.InvalidTestClassError
    }
    #endif
}
