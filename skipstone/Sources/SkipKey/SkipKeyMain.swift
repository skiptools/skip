import SkipBuild

/// Command-line runner for the Skip key processor
@main public struct SkipKeyMain {
    static func main() async throws {
        await SkipKeyExecutor.main()
    }
}
