import Foundation
import ArgumentParser
import TSCBasic
import SkipSyntax

struct DumpSkipCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(commandName: "ast-skip", abstract: "Print the Skip AST", shouldDisplay: false)

    @Option(name: [.customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    func run() async throws {
        var opts = CheckPhaseOptions()
        opts.symbols = symbols
        try await perform(on: files.map({ Source.FilePath(path: $0) }), options: opts)
    }

    func perform(on sourceFiles: [Source.FilePath], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.symbols))
            print(syntaxTree.prettyPrintTree)
        }
    }
}

