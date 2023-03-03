@testable import CrossFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class CrossUIGradleTests: GradleTestRunner {
    public func testCrossUI() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.app("CrossUI"), dependencies: [
            SkipTargetSet(.lib("CrossFoundation"), dependencies: [
                SkipTargetSet(.lib("SkipLib"))
            ])
        ]))
    }
}
