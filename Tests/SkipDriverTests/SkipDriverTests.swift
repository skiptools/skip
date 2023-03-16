// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import XCTest
@testable import SkipDriver

final class SkipDriverTests: XCTestCase {
    /// Check the output of `skiptool info`
    func testSkipTool() async throws {
        let info = try await SkipDriver.skipInfo()
        //print("info:", info)
        guard let cwdWritable = info["cwdWritable"] as? Bool else {
            return XCTFail("no cwdWritable key in info info dictionary")
        }
        XCTAssertEqual(true, cwdWritable, "cwd was not writable for tool")
    }
}
