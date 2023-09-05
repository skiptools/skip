// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
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
