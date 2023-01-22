import Foundation
import Skip
import SwiftParser
import SwiftSyntax

/// Command-line runner for the transpiler.
@main public struct Runner {
    static func main() throws {
        let arguments = CommandLine.arguments
        if !arguments.isEmpty {
            try run(Array(arguments.dropFirst())) // Drop executable argument
        }
    }

    /// Run the transpiler on the given arguments.
    public static func run(_ arguments: [String]) throws {
        let (action, files) = try processArguments(arguments)
        try action.perform(on: files)
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
    func perform(on files: [String]) throws
}

private struct PrintASTAction: Action {
    func perform(on files: [String]) throws {
        for file in files {
            let source = try String(contentsOfFile: file)
            let syntax = Parser.parse(source: source)
            print(syntax.root.prettyPrintTree)
        }
    }
}

private struct TranspileAction: Action {
    func perform(on files: [String]) {
        // TODO: Implement transpile action
    }
}
