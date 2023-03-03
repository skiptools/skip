@testable import CrossFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class SampleAppKip: GradleTestRunner {
    public func testSampleApp() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.app("SampleApp"), dependencies: [
            SkipTargetSet(.lib("CrossUI"), dependencies: [
                SkipTargetSet(.lib("CrossFoundation"), dependencies: [
                    SkipTargetSet(.lib("SkipLib"))
                ])
            ]),
            SkipTargetSet(.lib("SampleLib"), dependencies: [
                SkipTargetSet(.lib("CrossFoundation"), dependencies: [
                    SkipTargetSet(.lib("SkipLib"))
                ])
            ]),
        ]))
    }
}
