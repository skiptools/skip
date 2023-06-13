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
    ///   - compiler: the compiler to fork to evaluate the transpiled Kotlin; configured with the `KOTLINC` environment variable as a default
    ///   - replaceInlineSKIPME: when the kotlin source is set to `// SKIPME`, the generated Kotlin will be replaced in the project's source code file
    ///   - dependentModules: Simulate additional modules
    ///   - supportingSwift: additional swift to add to the block
    ///   - swift: raw static swift code for verification
    ///   - swiftCode: a Swift block, whose string contents will be used as the source of transpilation and which can return a validation string
    ///   - kotlin: the expected kotlin, or the literal `// SKIPME`
    ///   - packageSupportKotlin: the expected kotlin in the generated package support source file
    ///   - file: the file of the call site, expected to be `#file`
    ///   - line: the line of the call site, expected to be `#line`
    public func check(expectFailure: Bool = false, expectMessages: Bool = false, compiler: String? = ProcessInfo.processInfo.environment["KOTLINC"], replaceInlineSKIPME: Int? = 1, dependentModules: [CodebaseInfo] = [], supportingSwift: String? = nil, swift: StaticString? = nil, swiftCode: (() throws -> String?)? = nil, kotlin: String, fixup fixupKotlinBlock: ((String) -> (String)) = { $0 }, packageSupportKotlin: String? = nil, transformers: [KotlinTransformer] = builtinKotlinTransformers(), file: StaticString = #file, line: UInt = #line) async throws {

        func fixup(code: String) -> String {
            var code = fixupKotlinBlock(code)
            if swiftCode != nil {
                // inline swiftCode blocks create "internal fun" blocks, which aren't legal in swift script
                code = ("\n" + code)
                    .replacingOccurrences(of: "\ninternal ", with: "\n")
                    .replacingOccurrences(of: " internal ", with: " ")
                    .replacingOccurrences(of: "open fun ", with: "fun ")
                    .trimmingCharacters(in: .newlines)

                // various fixes to be able to compile without SkipLibKt
                code = code
                    .replacingOccurrences(of: ".sref()", with: "") // remove sref() calls
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
        codebaseInfo.dependentModules = dependentModules
        let tp = Transpiler(sourceFiles: srcFiles, codebaseInfo: codebaseInfo, transformers: transformers)
        var transpilations: [Transpilation] = []
        try await tp.transpile { transpilations.append($0) }
        guard !transpilations.isEmpty else {
            return XCTFail("transpilation produced no result", file: file, line: line)
        }

        var messages: [Message] = []
        for transpilation in transpilations {
            let messagesString = transpilation.messages.map(\.description).joined(separator: ",")
            messages += transpilation.messages
            if !transpilation.messages.isEmpty && !expectMessages && !expectFailure {
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
            } else if transpilation.sourceFile == srcFiles.first?.kotlinPackageSupport {
                if let packageSupportKotlin {
                    let content = fixup(code: trimmedContent(transpilation: transpilation))
                    let kotlinCode = packageSupportKotlin.trimmingCharacters(in: .whitespacesAndNewlines)
                    XCTAssertEqual(kotlinCode, content.trimmingCharacters(in: .whitespacesAndNewlines), messagesString, file: file, line: line)
                } else {
                    XCTFail("Transpilation produced unexpected package support content: \(transpilation.output.content)", file: file, line: line)
                }
            }
        }

        if messages.isEmpty {
            if expectMessages {
                XCTFail("Did not receive expected messages", file: file, line: line)
            }
        } else {
            messages.forEach { print("Received expected message: \($0)") }
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
    public func checkProducesMessage(preflight: Bool = false, swift: String, file: StaticString = #file, line: UInt = #line) async throws {
        let tmpFile = try tmpFile(named: "Source.swift", contents: swift)
        let srcFile = Source.FilePath(path: tmpFile.path)
        var messages: [Message] = []
        if preflight {
            let source = try Source(file: srcFile)
            let syntaxTree = SyntaxTree(source: source, unavailableAPI: KotlinUnavailableAPI())
            let transformers = builtinKotlinTransformers()
            transformers.forEach { $0.gather(from: syntaxTree) }
            transformers.forEach { $0.prepareForUse(codebaseInfo: nil) }
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            transformers.forEach { $0.apply(to: kotlinTree, translator: translator) }
            messages += kotlinTree.messages + transformers.flatMap { $0.messages(for: srcFile) }
        } else {
            let codebaseInfo = CodebaseInfo()
            let tp = Transpiler(sourceFiles: [srcFile], codebaseInfo: codebaseInfo, transformers: builtinKotlinTransformers())
            try await tp.transpile { transpilation in
                messages += transpilation.messages
            }
        }
        XCTAssertTrue(!messages.isEmpty)
        messages.forEach { print("Received expected message: \($0)") }
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
