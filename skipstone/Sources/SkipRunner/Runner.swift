import SkipBuild

/// Command-line runner for the transpiler.
@main public struct Runner {
    static func main() async throws {
        await SkipCommandExecutor.main()
    }
}
