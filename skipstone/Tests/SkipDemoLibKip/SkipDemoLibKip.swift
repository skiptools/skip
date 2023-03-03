@testable import SkipFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class SkipDemoLibKip: GradleTestRunner {
     func testSkipDemoLibKip() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("SkipDemoLib"), dependencies: [SkipTargetSet(.lib("SkipFoundation"), dependencies: [SkipTargetSet(.lib("SkipKotlin"))])]))
    }
}
