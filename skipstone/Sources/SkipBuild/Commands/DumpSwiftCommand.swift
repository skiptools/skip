import Foundation
import ArgumentParser
import TSCBasic
import SwiftParser
import SkipSyntax

struct DumpSwiftCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(commandName: "ast-swift", abstract: "Print the Swift AST", shouldDisplay: false)

    @Option(name: [.customShort("S")], help: ArgumentHelp("Preprocessor symbols", valueName: "file"))
    var symbols: [String] = []

    @Option(name: [.customShort("O")], help: ArgumentHelp("Output directory", valueName: "dir"))
    var directory: String? = nil

    @Argument(help: ArgumentHelp("List of files to process"))
    var files: [String]

    func run() async throws {
        var opts = CheckPhaseOptions()
        opts.directory = directory
        opts.symbols = symbols
        try await perform(on: files.map({ Source.FilePath(path: $0) }), options: opts)
    }

    func perform(on sourceFiles: [Source.FilePath], options: CheckPhaseOptions) async throws {
        for sourceFile in sourceFiles {
            let syntax = try Parser.parse(source: Source(file: sourceFile).content)
            print(syntax.root.prettyPrintTree)
        }
    }
}
