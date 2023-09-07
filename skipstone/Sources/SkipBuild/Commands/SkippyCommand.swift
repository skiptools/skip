import Foundation
import ArgumentParser
import TSCBasic
import SkipSyntax

struct SkippyCommand: AsyncParsableCommand, CheckPhase {
    static var configuration = CommandConfiguration(commandName: "skippy", abstract: "Perform transpilation preflight checks", shouldDisplay: false)

    @OptionGroup(title: "Check Options")
    var checkOptions: CheckPhaseOptions

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Option(help: ArgumentHelp("Suffix for output file", valueName: "suffix"))
    var outputSuffix: String?

    func run() async throws {
        try await perform(on: checkOptions.files.map({ Source.FilePath(path: $0) }), options: checkOptions)
    }

    func perform(on sourceFiles: [Source.FilePath], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.symbols), unavailableAPI: KotlinUnavailableAPI())
            let transformers = builtinKotlinTransformers()
            transformers.forEach { $0.gather(from: syntaxTree) }
            transformers.forEach { $0.prepareForUse(codebaseInfo: nil) }
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            transformers.forEach { $0.apply(to: kotlinTree, translator: translator) }

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
        return outputDir.appendingPathComponent(outputFileName)
    }
}
