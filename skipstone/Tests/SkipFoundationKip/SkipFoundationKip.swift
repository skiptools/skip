import SkipUnit
@testable import SkipFoundation

/// This test case will perform run the transpilation tests
final class SkipFoundationKip: GradleTestRunner {
    public func testSkipFoundationKip() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("SkipFoundation"), dependencies: [SkipTargetSet(.lib("SkipKotlin"))]))
    }
}
