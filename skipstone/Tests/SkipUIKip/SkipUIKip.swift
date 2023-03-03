@testable import SkipFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class SkipUIKip: GradleTestRunner {
    public func testSkipUIKip() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.app("SkipUI"), dependencies: [
            SkipTargetSet(.lib("SkipFoundation"), dependencies: [
                SkipTargetSet(.lib("SkipKotlin"))
            ])
        ]))
    }
}
