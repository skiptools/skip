import SkipBuild
@testable import SkipSyntax
import XCTest

extension XCTestCase {
    /// Whether to use the locally cached symbols for SkipLib syntax testing
    static let shouldUseLocalSymbols: Bool = true

    /// Checks that the given Swift compiles to the specified Kotlin.
    public func check(expectFailure: Bool = false, supportingSwift: String? = nil, swift: String, kotlin: String? = nil, file: StaticString = #file, line: UInt = #line) async throws {
        guard let kotlin else {
            return
        }

        #if os(Linux)
        // FIXME: symbol generation not currently working on linux, so tests that use symbols are disabled
        if symbols == nil {
            throw XCTSkip("symbol-reliant tests not yet working on Linux")
        }
        #endif

        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        var srcFiles = [Source.FilePath(path: srcFile.path)]
        if let supportingSwift {
            let supportingFile = try tmpFile(named: "Support.swift", contents: supportingSwift)
            srcFiles.append(Source.FilePath(path: supportingFile.path))
        }
        let codebaseInfo = CodebaseInfo()
        let tp = Transpiler(sourceFiles: srcFiles, codebaseInfo: codebaseInfo)
        try await tp.transpile { transpilation in
            let messagesString = transpilation.messages.map(\.description).joined(separator: ",")
            if !transpilation.messages.isEmpty && !expectFailure {
                XCTFail("Transpilation produced unexpected messages: \(messagesString)")
            }
            if transpilation.sourceFile == srcFiles.first {
                let content = trimmedContent(transpilation: transpilation)
                if expectFailure {
                    XCTExpectFailure()
                }
                XCTAssertEqual(kotlin.trimmingCharacters(in: .whitespacesAndNewlines), content.trimmingCharacters(in: .whitespacesAndNewlines), messagesString, file: file, line: line)
            }
        }
    }

    /// Checks that the given Swift generates a message when transpiled.
    public func checkProducesMessage(swift: String, file: StaticString = #file, line: UInt = #line) async throws {
        let srcFile = try tmpFile(named: "Source.swift", contents: swift)
        let codebaseInfo = CodebaseInfo()
        let tp = Transpiler(sourceFiles: [Source.FilePath(path: srcFile.path)], codebaseInfo: codebaseInfo)
        try await tp.transpile { transpilation in
            XCTAssertTrue(!transpilation.messages.isEmpty, trimmedContent(transpilation: transpilation))
            transpilation.messages.forEach { print("Received expected message: \($0)") }
        }
    }

    private func trimmedContent(transpilation: Transpilation) -> String {
        let content = transpilation.output.content
        let autoImportPrefix = "import skip.lib."
        return content.split(separator: "\n", omittingEmptySubsequences: false).filter({ !$0.hasPrefix(autoImportPrefix) }).joined(separator: "\n")
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
