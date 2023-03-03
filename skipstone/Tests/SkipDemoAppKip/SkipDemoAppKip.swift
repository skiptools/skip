@testable import SkipFoundation
import SkipUnit

/// This test case will perform run the transpilation tests
final class SkipDemoAppKip: GradleTestRunner {
    public func testSkipDemoAppKip() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.app("SkipDemoApp"), dependencies: [
            SkipTargetSet(.lib("SkipUI"), dependencies: [
                SkipTargetSet(.lib("SkipFoundation"), dependencies: [
                    SkipTargetSet(.lib("SkipKotlin"))
                ])
            ]),
            SkipTargetSet(.lib("SkipDemoLib"), dependencies: [
                SkipTargetSet(.lib("SkipFoundation"), dependencies: [
                    SkipTargetSet(.lib("SkipKotlin"))
                ])
            ]),
        ]))
    }
}
