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

    private static func processArguments(_ arguments: [String]) throws -> (Action, [String]) {
        var files: [String] = []
        var action: Action?
        for argument in arguments {
            if argument == "-printAST" {
                action = PrintASTAction()
            } else if argument.hasPrefix("-") {
                throw RunnerError(message: "Unrecognized option: \(argument)")
            } else {
                files.append(argument)
            }
        }
        return (action ?? TranspileAction(), files)
    }
}

private protocol Action {
    func perform(on files: [String]) async throws
}

private struct TranspileAction: Action {
    func perform(on files: [String]) async throws {
        let transpiler = Transpiler(inputFiles: files)
        try await transpiler.transpile { transpilation in
            print(transpilation.outputFile)
            print(String(repeating: "-", count: transpilation.outputFile.count))
            print(transpilation.code)
            print()
        }
    }
}

private struct PrintASTAction: Action {
    func perform(on files: [String]) async throws {
        for file in files {
            let source = try String(contentsOfFile: file)
            let syntax = Parser.parse(source: source)
            print(syntax.root.prettyPrintTree)
        }
    }
}
