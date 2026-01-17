// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import SkipBuild

/// Command-line runner for the transpiler.
@main public struct SkipRunnerMain {
    static func main() async throws {
        await SkipRunnerExecutor.main()
    }
}
