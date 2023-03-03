import SkipUnit
@testable import CrossFoundation

/// This test case will perform run the transpilation tests
final class CrossFoundationKotlinTests: GradleTestRunner {
    public func testCrossFoundationKotlin() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("CrossFoundation"), dependencies: [SkipTargetSet(.lib("SkipLib"))]))
    }
}
