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

extension FileSystem {
    /// Helper method to recurse the tree and perform the given block on each file.
    ///
    /// Note: `Task.isCancelled` is not checked; the controlling block should check for task cancellation.
    func recurse(path: AbsolutePath, block: (AbsolutePath) async throws -> ()) async throws {
        let contents = try getDirectoryContents(path)

        for entry in contents {
            let entryPath = path.appending(component: entry)
            try await block(entryPath)
            if isDirectory(entryPath) {
                try await recurse(path: entryPath, block: block)
            }
        }
    }

    /// Output the filesystem tree of the given path.
    func treeASCIIRepresentation(at path: AbsolutePath = .root) throws -> String {
        var writer: String = ""
        print(".", to: &writer)
        try treeASCIIRepresent(fs: self, path: path, to: &writer)
        return writer
    }

    /// Helper method to recurse and print the tree.
    private func treeASCIIRepresent<T: TextOutputStream>(fs: FileSystem, path: AbsolutePath, prefix: String = "", to writer: inout T) throws {
        let contents = try fs.getDirectoryContents(path)
        // content order is undefined, so we sort for a consistent output
        let entries = contents.sorted()

        for (idx, entry) in entries.enumerated() {
            let isLast = idx == entries.count - 1
            let line = prefix + (isLast ? "└─ " : "├─ ") + entry
            print(line, to: &writer)

            let entryPath = path.appending(component: entry)
            if fs.isDirectory(entryPath) {
                let childPrefix = prefix + (isLast ?  "   " : "│  ")
                try treeASCIIRepresent(fs: fs, path: entryPath, prefix: String(childPrefix), to: &writer)
            }
        }
    }
}

