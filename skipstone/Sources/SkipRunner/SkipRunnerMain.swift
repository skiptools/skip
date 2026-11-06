// Copyright (c) 2023 - 2026 Skip

import SkipBuild

/// Command-line runner for the transpiler.
@main public struct SkipRunnerMain {
    static func main() async throws {
        await SkipRunnerExecutor.main()
    }
}
