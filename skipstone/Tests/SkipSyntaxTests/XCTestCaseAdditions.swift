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
    ///   - dependentModules: Simulate additional modules
    ///   - supportingSwift: additional swift to add to the block but not include in the expected output
    ///   - swift: raw static swift code for verification
    ///   - swiftCode: a Swift block, whose string contents will be used as the source of transpilation and which can return a validation string
    ///   - isSwiftBridge: whether the given Swift code is only for bridging, not for transpilation
    ///   - kotlin: the expected kotlin
    ///   - kotlinPackageSupport: the expected kotlin in the generated package support source file
    ///   - swiftBridgeSupport: the expected swift in the generated bridge file
    ///   - file: the file of the call site, expected to be `#file`
    ///   - line: the line of the call site, expected to be `#line`
    public func check(expectFailure: Bool = false, expectMessages: Bool = false, compiler: String? = ProcessInfo.processInfo.environment["KOTLINC"], dependentModules: [CodebaseInfo.ModuleExport] = [], supportingSwift: String? = nil, swift: StaticString? = nil, swiftCode: (() throws -> String?)? = nil, swiftBridge: String? = nil, kotlin: String? = nil, kotlins: [String] = [], fixup fixupKotlinBlock: ((String) -> (String)) = { $0 }, kotlinPackageSupport: String? = nil, swiftBridgeSupport: String? = nil, swiftBridgeSupports: [String] = [], transformers: [KotlinTransformer] = builtinKotlinTransformers(), file: StaticString = #file, line: UInt = #line) async throws {
        
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
        let swiftBridgeString = swiftBridge?.description ?? ""
        
        // the URL of the test case call site, which is used to extract Swift blocks
        let sourceURL = URL(fileURLWithPath: file.description)
        if swift == nil && swiftBridge == nil {
            if swiftCode == nil {
                // ensure that we have specified a block
                return XCTFail("must specify either `swift` or `swiftCode` block", file: file, line: line)
            }
            
            // get the swift string by extracting it from the line of the call site in the source file
            let sourceFileContents = try String(contentsOf: sourceURL, encoding: .utf8)
            var swiftCodeBlock = false
            for (fileLine, sourceLine) in sourceFileContents.components(separatedBy: .newlines).enumerated() {
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
        
        if swiftString.isEmpty && swiftBridgeString.isEmpty {
            return XCTFail("must specify either `swift` or `swiftCode` block, or `swiftBridge`", file: file, line: line)
        }
        
        var srcFiles: [Source.FilePath] = []
        if !swiftString.isEmpty {
            let srcFile = try tmpFile(named: "Source.swift", contents: swiftString)
            srcFiles.append(Source.FilePath(path: srcFile.path))
        }
        var bridgeFiles: [Source.FilePath] = []
        if !swiftBridgeString.isEmpty {
            let srcFile = try tmpFile(named: "Bridge.swift", contents: swiftBridgeString)
            bridgeFiles.append(Source.FilePath(path: srcFile.path))
        }
        if let supportingSwift, !supportingSwift.isEmpty {
            let srcFile = try tmpFile(named: "Support.swift", contents: supportingSwift)
            srcFiles.append(Source.FilePath(path: srcFile.path))
        }
        let codebaseInfo = CodebaseInfo()
        codebaseInfo.dependentModules = dependentModules
        let tp = Transpiler(transpileFiles: srcFiles, bridgeFiles: bridgeFiles, codebaseInfo: codebaseInfo, transformers: transformers)
        var transpilations: [Transpilation] = []
        try await tp.transpile { transpilations.append($0) }
        guard !transpilations.isEmpty else {
            return XCTFail("transpilation produced no result", file: file, line: line)
        }
        
        var kotlinTranspilations: [Transpilation] = []
        var kotlinMessagesString = ""
        var swiftBridgeTranspilations: [Transpilation] = []
        var swiftBridgeMessagesString = ""
        var messages: [Message] = []
        for transpilation in transpilations {
            let messagesString = transpilation.messages.map(\.formattedMessage).joined(separator: ",")
            messages += transpilation.messages
            if !transpilation.messages.isEmpty && !expectMessages && !expectFailure {
                XCTFail("Transpilation produced unexpected messages: \(messagesString)", file: file, line: line)
            }
            if transpilation.output.file.isBridgeOutputFile {
                swiftBridgeTranspilations.append(transpilation)
                if !swiftBridgeMessagesString.isEmpty {
                    swiftBridgeMessagesString += "\n"
                }
                swiftBridgeMessagesString += messagesString
            } else if transpilation.input.file == srcFiles.first || transpilation.input.file == bridgeFiles.first {
                kotlinTranspilations.append(transpilation)
                if !kotlinMessagesString.isEmpty {
                    kotlinMessagesString += "\n"
                }
                kotlinMessagesString += messagesString
            } else if transpilation.input.file == (srcFiles.first ?? bridgeFiles.first)?.kotlinPackageSupport(tests: false) {
                if let kotlinPackageSupport {
                    let content = fixup(code: trimmedContent(transpilation: transpilation))
                    let expectedKotlin = kotlinPackageSupport.trimmingCharacters(in: .whitespacesAndNewlines)
                    XCTAssertEqual(expectedKotlin, content.trimmingCharacters(in: .whitespacesAndNewlines), messagesString, file: file, line: line)
                } else {
                    XCTFail("Transpilation produced unexpected package support content: \(transpilation.output.content)", file: file, line: line)
                }
            }
        }
        
        var expectedKotlin: [String]
        if let kotlin, !kotlin.isEmpty {
            expectedKotlin = [kotlin.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            expectedKotlin = kotlins.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        var generatedKotlin = kotlinTranspilations
            .sorted { $0.output.file.name < $1.output.file.name }
            .map { fixup(code: trimmedContent(transpilation: $0)).trimmingCharacters(in: .whitespacesAndNewlines) }
        if expectFailure {
            if messages.isEmpty {
                let allExpectedKotlin = expectedKotlin.joined(separator: "\n")
                let allGeneratedKotlin = generatedKotlin.joined(separator: "\n")
                XCTAssertNotEqual(allExpectedKotlin, allGeneratedKotlin, kotlinMessagesString, file: file, line: line)
            }
        } else {
            while expectedKotlin.count < generatedKotlin.count {
                expectedKotlin.append("")
            }
            while generatedKotlin.count < expectedKotlin.count {
                generatedKotlin.append("")
            }
            for i in 0..<generatedKotlin.count {
                XCTAssertEqual(expectedKotlin[i], generatedKotlin[i], kotlinMessagesString, file: file, line: line)
            }
        }

        var expectedSwiftBridgeSupport: [String]
        if let swiftBridgeSupport, !swiftBridgeSupport.isEmpty {
            expectedSwiftBridgeSupport = [swiftBridgeSupport.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            expectedSwiftBridgeSupport = swiftBridgeSupports.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        expectedSwiftBridgeSupport = expectedSwiftBridgeSupport.map {
            if $0.isEmpty {
                return $0
            } else {
                return "#if canImport(SkipBridge)\nimport SkipBridge\n\n" + $0 + "\n\n#endif"
            }
        }
        var generatedSwiftBridgeSupport = swiftBridgeTranspilations
            .sorted { $0.output.file.name < $1.output.file.name }
            .map { $0.output.content.trimmingCharacters(in: .whitespacesAndNewlines) }
        while expectedSwiftBridgeSupport.count < generatedSwiftBridgeSupport.count {
            expectedSwiftBridgeSupport.append("")
        }
        while generatedSwiftBridgeSupport.count < expectedSwiftBridgeSupport.count {
            generatedSwiftBridgeSupport.append("")
        }
        for i in 0..<generatedSwiftBridgeSupport.count {
            XCTAssertEqual(expectedSwiftBridgeSupport[i], generatedSwiftBridgeSupport[i], swiftBridgeMessagesString, file: file, line: line)
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
        var kotlinLines = fixup(code: expectedKotlin.joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        if var lastLine = kotlinLines.last {
            // take the expected "return" from the final line and convert it to the `print` statement as the means for kotlinc to convey the return value back to the program as part of the stdout return from `Process.checkNonZeroExit`
            lastLine = lastLine.replacingOccurrences(of: "return ", with: "print(") + ")" // 'return "yes"' -> 'print("yes")'
            kotlinLines = kotlinLines.dropLast(1) + [lastLine]
        }
        let kotlinResult = try await kotlinc(compiler: compiler, source: kotlinLines.joined(separator: "\n"), script: true)

        if let swiftCode = swiftCode, let swiftResult = try swiftCode() {
            XCTAssertEqual(swiftResult, kotlinResult, file: file, line: line)
        }
    }

    /// Checks that the given Swift generates a message when transpiled.
    public func checkProducesMessage(preflight: Bool = false, swift: String, isSwiftBridge: Bool = false) async throws {
        let tmpFile = try tmpFile(named: "Source.swift", contents: swift)
        let messages = try await transpile(preflight: preflight, files: [tmpFile], isSwiftBridge: isSwiftBridge)
        XCTAssertTrue(!messages.isEmpty)
        messages.forEach { print("Received expected message: \($0)") }
    }

    /// Transpiles the code without performing checks, e.g. for performance profiling.
    @discardableResult public func transpile(preflight: Bool = false, files: [URL], isSwiftBridge: Bool = false, dependentModules: [CodebaseInfo.ModuleExport] = []) async throws -> [Message] {
        let srcFiles = files.map { Source.FilePath(path: $0.absoluteURL.path) }
        let transformers = builtinKotlinTransformers()
        var messages: [Message] = []
        if preflight {
            for srcFile in srcFiles {
                let source = try Source(file: srcFile)
                let syntaxTree = SyntaxTree(source: source, isBridgeFile: isSwiftBridge, unavailableAPI: KotlinUnavailableAPI())
                transformers.forEach { $0.gather(from: syntaxTree) }
                transformers.forEach { $0.prepareForUse(codebaseInfo: nil) }
                let translator = KotlinTranslator(syntaxTree: syntaxTree)
                let kotlinTree = translator.translateSyntaxTree()
                transformers.forEach { let _ = $0.apply(to: kotlinTree, translator: translator) }
                messages += kotlinTree.messages + transformers.flatMap { $0.messages(for: srcFile) }
            }
        } else {
            let codebaseInfo = CodebaseInfo()
            codebaseInfo.dependentModules = dependentModules
            let tp = Transpiler(transpileFiles: isSwiftBridge ? [] : srcFiles, bridgeFiles: isSwiftBridge ? srcFiles : [], codebaseInfo: codebaseInfo, transformers: transformers)
            try await tp.transpile { transpilation in
                messages += transpilation.messages
            }
        }
        return messages
    }

    private func trimmedContent(transpilation: Transpilation) -> String {
        let content = transpilation.output.content
        let autoImport = "import skip.lib.*"
        return content.split(separator: "\n", omittingEmptySubsequences: false).filter({ $0 != autoImport }).joined(separator: "\n")
    }

    /// Creates a temporary file with the given name and optional contents.
    public func tmpFile(named fileName: String, tmpDirectoryName: String? = nil, contents: String? = nil) throws -> URL {
        let tmpDir = URL(fileURLWithPath: tmpDirectoryName ?? UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: (tmpDirectoryName != nil ? "/tmp" : NSTemporaryDirectory()) + "/SkipSyntaxTests/", isDirectory: true))
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
