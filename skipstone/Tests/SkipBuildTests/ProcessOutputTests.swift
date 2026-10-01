// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import SkipBuild

final class ProcessOutputTests: XCTestCase {
    func testDuplicatedSkipLibrariesHint() throws {
        // the swiftbuild error for Skip framework releases that predate SKIP_DYNAMIC_LIBRARIES (https://github.com/skiptools/skip/issues/714)
        let stderr = """
        error: Swift package product 'SkipLib-product' is linked as a static library by 'SkipAndroidBridge-product' and 'SkipBridge-product'. This will result in duplication of library code.
        error: Swift package product 'SkipUnit-product' is linked as a static library by 'SkipAndroidBridge-product' and 'SkipBridge-product'. This will result in duplication of library code.
        """
        let errorLine = try XCTUnwrap(ProcessOutput(exitCode: 1, stdout: "", stderr: stderr).scanErrorLine())
        XCTAssertTrue(errorLine.hasPrefix("error: Swift package product 'SkipLib-product'"))
        XCTAssertTrue(errorLine.hasSuffix(ProcessOutput.duplicatedSkipLibrariesHint), "hint should be appended once, after the errors")
        XCTAssertEqual(errorLine.components(separatedBy: ProcessOutput.duplicatedSkipLibrariesHint).count, 2, "hint should appear exactly once")

        // unrelated errors are passed through without the hint
        XCTAssertEqual(ProcessOutput(exitCode: 1, stdout: "", stderr: "error: no such module 'Foo'").scanErrorLine(), "error: no such module 'Foo'")
    }
}
