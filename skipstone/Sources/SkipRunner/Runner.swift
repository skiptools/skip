import Foundation
import Skip
import SwiftParser
import SwiftSyntax

/// Command-line runner for the transpiler.
@main public struct Runner {
    static func main() async throws {
        let arguments = CommandLine.arguments
        if !arguments.isEmpty {
            try await run(Array(arguments.dropFirst())) // Drop executable argument
        }
    }

    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String]) async throws {
        let (action, options, files) = try processArguments(arguments)
        try await action.perform(on: files, options: options)
    }

    private static func processArguments(_ arguments: [String]) throws -> (Action, Options, [Source.File]) {
        var files: [Source.File] = []
        var action: Action?
        var options = Options()
        for argument in arguments {
            if argument == "-skippy" {
                action = SkippyAction()
            } else if argument == "-swiftAST" {
                action = PrintSwiftASTAction()
            } else if argument == "-skipAST" {
                action = PrintSkipASTAction()
            } else if argument.hasPrefix("-D") && argument.count > 2 {
                options.preprocessorSymbols.append(String(argument.dropFirst(2)))
            } else if argument.hasPrefix("-O") && argument.count > 2 {
                options.outputDirectory = String(argument.dropFirst(2))
            } else if argument.hasPrefix("-") {
                throw RunnerError(message: "Unrecognized option: \(argument)")
            } else {
                let source = Source.File(path: argument)
                if source.isSwift {
                    files.append(source)
                }
            }
        }
        return (action ?? TranspileAction(), options, files)
    }
}

private protocol Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws
}

private struct Options {
    var preprocessorSymbols: [String] = []
    var outputDirectory: String?
}

private struct TranspileAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        var transpiler = Transpiler(sourceFiles: sourceFiles)
        transpiler.preprocessorSymbols = Set(options.preprocessorSymbols)
        try await transpiler.transpile { transpilation in
            for message in transpilation.messages {
                print(message)
            }
            print(transpilation.output.content)
            print()
        }
    }
}

private struct SkippyAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        for sourceFile in sourceFiles {
            print("RUNNING ON: \(sourceFile.path)") //~~~
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.preprocessorSymbols))
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            kotlinTree.messages.forEach { print($0) }

            // Xcode requires that we create an output file in order for incremental build tools to work
            if let outputDir = options.outputDirectory {
                let outputFileURL = URL(fileURLWithPath: outputDir).appendingPathComponent(source.file.outputFile(withExtension: "skip").name)
                try Date().description.write(to: outputFileURL, atomically: false, encoding: .utf8)
            }
        }
    }
}

private struct PrintSwiftASTAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        for sourceFile in sourceFiles {
            let syntax = try Parser.parse(source: Source(file: sourceFile).content)
            print(syntax.root.prettyPrintTree)
        }
    }
}

private struct PrintSkipASTAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.preprocessorSymbols))
            print(syntaxTree.prettyPrintTree)
        }
    }
}
