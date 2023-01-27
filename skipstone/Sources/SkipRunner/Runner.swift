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
        let (action, files) = try processArguments(arguments)
        try await action.perform(on: files)
    }

    private static func processArguments(_ arguments: [String]) throws -> (Action, [Source.File]) {
        var files: [Source.File] = []
        var action: Action?
        for argument in arguments {
            if argument == "-printAST" {
                action = PrintASTAction()
            } else if argument.hasPrefix("-") {
                throw RunnerError(message: "Unrecognized option: \(argument)")
            } else {
                let source = Source.File(path: argument)
                if source.isSwift {
                    files.append(source)
                }
            }
        }
        return (action ?? TranspileAction(), files)
    }
}

private protocol Action {
    func perform(on sourceFiles: [Source.File]) async throws
}

private struct TranspileAction: Action {
    func perform(on sourceFiles: [Source.File]) async throws {
        let transpiler = Transpiler(sourceFiles: sourceFiles)
        try await transpiler.transpile { transpilation in
            for message in transpilation.messages {
                print(message)
            }
            print(transpilation.output.content)
            print()
        }
    }
}

private struct PrintASTAction: Action {
    func perform(on sourceFiles: [Source.File]) async throws {
        for sourceFile in sourceFiles {
            let syntax = try Parser.parse(source: Source(file: sourceFile).content)
            print(syntax.root.prettyPrintTree)
        }
    }
}
