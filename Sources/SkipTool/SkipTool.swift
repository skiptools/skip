import SkipBuild

/// Command-line runner for the transpiler.
@main public struct SkipTool {
    static func main() async throws {
        await SkipCommandExecutor.main()
    }
}
