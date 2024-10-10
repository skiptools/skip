import Foundation
import ArgumentParser
import TSCBasic
import SkipSyntax

struct SkippyCommand: TranspilerInputOptionsCommand {
    /// The "CONFIGURATION" parameter specifies whether we are to run in Skippy mode or full-transpile mode
    static let skippyOnly = ProcessInfo.processInfo.environment["CONFIGURATION"] == "Skippy"

    static var configuration = CommandConfiguration(commandName: "skippy", abstract: "Perform transpilation preflight checks", shouldDisplay: false)

    @OptionGroup(title: "Check Options")
    var inputOptions: TranspilerInputOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Option(help: ArgumentHelp("Suffix for output file", valueName: "suffix"))
    var outputSuffix: String?

    @Option(help: ArgumentHelp("Allow missing source files", valueName: "allow"))
    var allowMissingSources: Bool = true

    func run() async throws {
        try await perform(on: inputOptions.files.map({ Source.FilePath(path: $0) }), options: inputOptions)
    }

    func perform(on candidateSourceFiles: [Source.FilePath], options: TranspilerInputOptions) async throws {
        // due to FB12969712 https://github.com/apple/swift-package-manager/issues/6816 , we need to tolerate missing source files because Xcode sends the same cached list of sources regardless of changes to the underlying project structure
        let sourceFiles = candidateSourceFiles.filter({
            !allowMissingSources || FileManager.default.fileExists(atPath: $0.path)
        })

        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.symbols), unavailableAPI: KotlinUnavailableAPI())
            let transformers = builtinKotlinTransformers()
            transformers.forEach { $0.gather(from: syntaxTree) }
            transformers.forEach { $0.prepareForUse(codebaseInfo: nil) }
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            transformers.forEach { _ = $0.apply(to: kotlinTree, translator: translator) }

            let messages = kotlinTree.messages + transformers.flatMap { $0.messages(for: sourceFile) }
            messages.forEach { print($0) }

            if let outputDir = options.directory {
                let outputDirURL = URL(fileURLWithPath: outputDir, isDirectory: true)
                if let outputFileURL = outputFileURL(for: sourceFile, in: outputDirURL) {
                    if (try? outputDirURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                        try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)
                    }
                    // the output file is just empty data
                    try Data().write(to: outputFileURL)
                }
            }
        }
    }

    /// Xcode requires that we create an output file in order for incremental build tools to work.
    func outputFileURL(for sourceFile: Source.FilePath, in outputDir: URL) -> URL? {
        guard let outputSuffix = outputSuffix else {
            return nil
        }
        var outputFileName = sourceFile.name
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(outputFileName.dropLast(".swift".count))
        }
        outputFileName += outputSuffix
        return outputDir.appendingPathComponent("." + outputFileName, isDirectory: false)
    }
}
