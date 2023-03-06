@testable import CrossFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class ExampleAppKotlinTests : GradleTestRunner {
    public func testExampleApp() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.app("ExampleApp"), dependencies: [
            SkipTargetSet(.lib("CrossUI"), dependencies: [
                SkipTargetSet(.lib("CrossFoundation"), dependencies: [
                    SkipTargetSet(.lib("SkipLib"))
                ])
            ]),
            SkipTargetSet(.lib("ExampleLib"), dependencies: [
                SkipTargetSet(.lib("CrossFoundation"), dependencies: [
                    SkipTargetSet(.lib("SkipLib"))
                ])
            ]),
        ]))
    }
}
