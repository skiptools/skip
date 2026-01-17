// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import SkipBuild
import TSCBasic

final class SkipAssemberTests: XCTestCase {
    public func testFileSystem() async throws {
        try fileSystemTest(fs: InMemoryFileSystem())
        try fileSystemTest(fs: localFileSystem)
    }

    public func fileSystemTest<FS: FileSystem>(fs: FS) throws {
        let tmpRoot = try AbsolutePath(validating: UUID().uuidString, relativeTo: AbsolutePath(validating: NSTemporaryDirectory()))

        let baseDir = try AbsolutePath(validating: "one/two/three", relativeTo: tmpRoot)
        try fs.createDirectory(baseDir, recursive: true)
        let dummyFile = baseDir.appending(component: "basic.txt")
        try fs.writeFileContents(dummyFile) { stream in
            stream.write("Hello World")
        }
        let contents = try fs.readFileContents(dummyFile)
        XCTAssertEqual("Hello World", contents)

        XCTAssertEqual(try fs.treeASCIIRepresentation(at: tmpRoot), """
        .
        └─ one
           └─ two
              └─ three
                 └─ basic.txt

        """)

        let reroot = RerootedFileSystemView(fs, rootedAt: baseDir)
        try reroot.writeFileContents(AbsolutePath(validating: "/advanced.txt")) { stream in
            stream.write("Hello Advanced")
        }

        XCTAssertEqual(try fs.treeASCIIRepresentation(at: tmpRoot), """
        .
        └─ one
           └─ two
              └─ three
                 ├─ advanced.txt
                 └─ basic.txt

        """)


        try fs.removeFileTree(tmpRoot)
    }
}

