// Copyright 2023 Skip
#if !canImport(SkipBuild)
#error("Should only import SkipBuild for SKIPLOCAL")
#else
import SkipBuild

/// The plugin runner for the command-line `skip` tool when executed in the plugin environment.
@main public struct SkipToolMain {
    static func main() async throws {
        await SkipRunnerExecutor.main()
    }
}
#endif
