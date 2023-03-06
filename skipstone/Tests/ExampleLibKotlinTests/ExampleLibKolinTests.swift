@testable import CrossFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class ExampleAppGradleTests: GradleTestRunner {
     func testExampleApp() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("ExampleLib"), dependencies: [SkipTargetSet(.lib("CrossFoundation"), dependencies: [SkipTargetSet(.lib("SkipLib"))])]))
    }
}
