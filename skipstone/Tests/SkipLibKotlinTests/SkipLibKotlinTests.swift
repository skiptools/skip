import SkipUnit

/// This test case will perform run the transpilation tests
final class SkipLibKotlinTests: GradleTestRunner {
    public func testSkipLibKotlin() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("SkipLib")))
    }
}
