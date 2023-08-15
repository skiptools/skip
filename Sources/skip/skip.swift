// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Affero General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import SkipDrive

/// Command-line runner for the transpiler.
///
/// This is only built for local `skiptool` imported through `SKIPLOCAL` (see `Package.swift`).
@main public struct SkipMain {
    static func main() async throws {
        //await SkipRunnerExecutor.main()
        print("Running Skip Command")
    }
}
