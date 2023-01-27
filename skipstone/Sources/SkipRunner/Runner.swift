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
            if argument == "-swiftAST" {
                action = PrintSwiftASTAction()
            } else if argument == "-skipAST" {
                action = PrintSkipASTAction()
            } else if argument == "-kotlinAST" {
                action = PrintKotlinASTAction()
            } else if argument.hasPrefix("-D") && argument.count > 2 {
                options.preprocessorSymbols.append(String(argument.dropFirst(2)))
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

private struct PrintKotlinASTAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        let codebaseInfo = CodebaseInfo()
        var syntaxTrees: [SyntaxTree] = []
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.preprocessorSymbols))
            codebaseInfo.gather(from: syntaxTree)
            syntaxTrees.append(syntaxTree)
        }
        for syntaxTree in syntaxTrees {
            let translator = KotlinTranslator(syntaxTree: syntaxTree, codebaseInfo: codebaseInfo)
            let kotlinAST = translator.translateSyntaxTree()
            print(kotlinAST.prettyPrintTree)
        }
    }
}
