@testable import Skip
import XCTest

extension XCTestCase {
    /// Checks that the given Swift compiles to the specified Kotlin.
    public func check(swift: String, kotlin: String? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        if let kotlin = kotlin {
            let tp = Transpiler(sourceFiles: [Source.File(path: srcFile.path)])
            try await tp.transpile { transpilation in
                //print("transpilation:", transpilation.output)
                var content = transpilation.output.content
                let autoImportPrefix = "import skip.kotlin."
                content = content.split(separator: "\n", omittingEmptySubsequences: false).filter({ !$0.hasPrefix(autoImportPrefix) }).joined(separator: "\n")
                XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), content.trimmingCharacters(in: .whitespacesAndNewlines), file: file, line: line)
            }
        }
    }

    /// Creates a temporary file with the given name and optional contents.
    public func tmpFile(named fileName: String, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmpFile = URL(fileURLWithPath: fileName, isDirectory: false, relativeTo: tmpDir)
        if let contents = contents {
            try contents.write(to: tmpFile, atomically: true, encoding: .utf8)
        }
        return tmpFile
    }
}
