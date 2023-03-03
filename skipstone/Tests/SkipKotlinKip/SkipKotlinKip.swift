import SkipUnit

/// This test case will perform run the transpilation tests
final class SkipKotlinKip: GradleTestRunner {
    public func testSkipKotlinKip() async throws {
        try await transpileAndTest(targets: SkipTargetSet(.lib("SkipKotlin")))
    }
}
