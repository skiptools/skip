@testable import CrossFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class SampleAppGradleTests: GradleTestRunner {
     func testSampleApp() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("SampleLib"), dependencies: [SkipTargetSet(.lib("CrossFoundation"), dependencies: [SkipTargetSet(.lib("SkipLib"))])]))
    }
}
