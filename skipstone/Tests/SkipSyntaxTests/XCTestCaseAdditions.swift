import SkipBuild
@testable import SkipSyntax
import TSCBasic
import XCTest

extension XCTestCase {
    /// Checks that the given Swift transpiles to the expected Kotlin.
    ///
    /// The Swift source can be either a literal `swift` string,
    /// or it can be a `swiftCode` closure returning an optional string,
    /// in which case the source `file` will be parsed to extract and transpile the swift. In this case,
    /// and with the `compiler` argument (defaulting to the "KOTLINC" environment property),
    /// the `kotlinc -script` command will be forked and the Kotlin code will be evaluated to a string,
    /// and that string will be assessed for equality against the evaluation of the `swiftCode` closure.
    ///
    /// - Parameters:
    ///   - expectFailure: if `true`, expect that the match will fail
    ///   - supportingSwift: additional swift to add to the block
    ///   - swift: raw static swift code for verification
    ///   - swiftCode: a Swift block, whose string contents will be used as the source of transpilation and which can return a validation string
    ///   - compiler: the compiler to fork to evaluate the transpiled Kotlin; configured with the `KOTLINC` environment variable as a default
    ///   - replaceInlineSKIPME: when the kotlin source is set to `// SKIPME`, the generated Kotlin will be replaced in the project's source code file
    ///   - kotlin: the expected kotlin, or the literal `// SKIPME` when the
    ///   - file: the file of the call site, expected to be `#file`
    ///   - line: the line of the call site, expected to be `#line`
    public func check(expectFailure: Bool = false, compiler: String? = ProcessInfo.processInfo.environment["KOTLINC"], replaceInlineSKIPME: Int? = 1, supportingSwift: String? = nil, swift: StaticString? = nil, swiftCode: (() throws -> String?)? = nil, kotlin: String, fixup fixupKotlinBlock: ((String) -> (String)) = { $0 }, plugins: [KotlinPlugin] = [], file: StaticString = #file, line: UInt = #line) async throws {

        func fixup(code: String) -> String {
            var code = fixupKotlinBlock(code)
            if swiftCode != nil {
                // inline swiftCode blocks create "internal fun" blocks, which aren't legal in swift script
                code = ("\n" + code)
                    .replacingOccurrences(of: "\ninternal ", with: "\n")
                    .replacingOccurrences(of: " internal ", with: " ")
                    .trimmingCharacters(in: .newlines)
            }
            return code
        }

        var swiftString = swift?.description ?? ""

        // the URL of the test case call site, which is used to extract Swift blocks and potentially auto-update SKIPME kotlin
        let sourceURL = URL(fileURLWithPath: file.description)
        func sourceFileContents() throws -> String {
            try String(contentsOf: sourceURL, encoding: .utf8)
        }

        if swift == nil {
            if swiftCode == nil {
                // ensure that we have specified a block
                return XCTFail("must specify either `swift` or `swiftCode` block", file: file, line: line)
            }

            // get the swift string by extracting it from the line of the call site in the source file
            var swiftCodeBlock = false
            for (fileLine, sourceLine) in try sourceFileContents().components(separatedBy: .newlines).enumerated() {
                if fileLine < Int(line) - 1 {
                    continue
                } else if !swiftCodeBlock {
                    //print("checking for swiftcode line: \(fileLine) (vs. \(line)): \(sourceLine)")
                    swiftCodeBlock = sourceLine.trimmingCharacters(in: .whitespaces).hasSuffix("swiftCode: {")
                } else if swiftCodeBlock {
                    // keep going until we see the matching "kotlin" arg below
                    if sourceLine.trimmingCharacters(in: .whitespaces).hasPrefix("}, kotlin:") {
                        break
                    } else {
                        swiftString += sourceLine
                    }
                }
            }
        }

        if swiftString.isEmpty {
            return XCTFail("must specify either `swift` or `swiftCode` block", file: file, line: line)
        }

        let srcFile = try tmpFile(named: "Source.swift", contents: swiftString)
        var srcFiles = [Source.FilePath(path: srcFile.path)]
        if let supportingSwift {
            let supportingFile = try tmpFile(named: "Support.swift", contents: supportingSwift)
            srcFiles.append(Source.FilePath(path: supportingFile.path))
        }
        let codebaseInfo = CodebaseInfo()
        let tp = Transpiler(sourceFiles: srcFiles, codebaseInfo: codebaseInfo, plugins: plugins)
        var transpilations: [Transpilation] = []
        try await tp.transpile { transpilations.append($0) }
        guard let transpilation = transpilations.first else {
            return XCTFail("transpilation produced no result", file: file, line: line)
        }

        let messagesString = transpilation.messages.map(\.description).joined(separator: ",")
        if !transpilation.messages.isEmpty && !expectFailure {
            XCTFail("Transpilation produced unexpected messages: \(messagesString)", file: file, line: line)
        }
        if transpilation.sourceFile == srcFiles.first {
            let content = fixup(code: trimmedContent(transpilation: transpilation))
            let kotlinCode = kotlin.trimmingCharacters(in: .whitespacesAndNewlines)

            // insert the Kotlin code in the test case where it says // SKIPME
            if var skipmeCount = replaceInlineSKIPME, skipmeCount > 0 {
                if kotlinCode == "// SKIPME" {
                    // insert the Kotlin code where it says SKIPME, but indent so it lines up with the Swift multi-line string
                    let sourceContents = try sourceFileContents()
                    var testSourceOutput = ""
                    for sourceLine in sourceContents.components(separatedBy: .newlines) {
                        if skipmeCount > 0,
                           sourceLine.trimmingCharacters(in: .whitespaces) == "// SKIPME" {
                            let leadingSpace = sourceLine.enumerated().first(where: { $0.element != " " })?.offset ?? 0
                            let pad = String(repeating: " ", count: leadingSpace)
                            let indentedContent = content
                                .trimmingCharacters(in: .newlines)
                                .components(separatedBy: .newlines)
                                .map({ pad + $0 })
                                .joined(separator: "\n")
                            testSourceOutput += indentedContent + "\n"
                            skipmeCount += 1
                        } else {
                            testSourceOutput += sourceLine + "\n"
                        }
                    }

                    if sourceContents != testSourceOutput {
                        print("saving updated SKIPME source to:", sourceURL)
                        try testSourceOutput.write(to: sourceURL, atomically: true, encoding: .utf8)
                    }
                }
            }

            if expectFailure {
                XCTAssertNotEqual(kotlinCode, content.trimmingCharacters(in: .whitespacesAndNewlines), messagesString, file: file, line: line)
            } else {
                XCTAssertEqual(kotlinCode, content.trimmingCharacters(in: .whitespacesAndNewlines), messagesString, file: file, line: line)
            }
        }

        // if we spcify to fork the kotlinc compiler, proceed with evaluating and comparing the results
        guard let compiler, swiftCode != nil else {
            return
        }

        // post-process the kotlin lines
        var kotlinLines = fixup(code: kotlin).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        if var lastLine = kotlinLines.last {
            // take the expected "return" from the final line and convert it to the `print` statement as the means for kotlinc to convey the return value back to the program as part of the stdout return from `Process.checkNonZeroExit`
            lastLine = lastLine.replacingOccurrences(of: "return ", with: "print(") + ")" // 'return "yes"' -> 'print("yes")'
            kotlinLines = kotlinLines.dropLast(1) + [lastLine]
        }
        let kotlinResult = try await kotlinc(compiler: compiler, source: kotlinLines.joined(separator: "\n"), script: true)

        if let swiftCode = swiftCode,
           let swiftResult = try swiftCode() {
            
            XCTAssertEqual(swiftResult, kotlinResult, file: file, line: line)
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

    /// Compiles the given Kotlin source and evaluates it as a script, returning the result.
    @discardableResult public func kotlinc(compiler: String, sourceName: String = "Source", source kotlin: String, script: Bool = true) async throws -> String {
        let file = try tmpFile(named: script ? "\(sourceName).kts" : "\(sourceName).kt", contents: kotlin)
        let env: [String: String] = [:]
        let args = [
            compiler,
            script ? "-script" : nil,
            file.path,
        ].compactMap({ $0 })

        do {
            let result = try await Process.checkNonZeroExit(arguments: args, environment: env, loggingHandler: { msg in
                print("kotlinc> " + msg)
            })

            //print("kotlinc result:", result, separator: "\n")
            return result
        } catch {
            print("kotlinc error: \(error)")
            throw error
        }

    }
}
