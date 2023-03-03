import Foundation
import SkipSyntax
import SwiftParser
import SwiftSyntax
import ArgumentParser
import SkipBuild

/// The current versio of the tool
public let skipVersion = "0.0.34"

struct MyCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "mycommand",
        abstract: "My command-line tool",
        subcommands: [Subcommand.self])

    struct Subcommand: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "subcommand",
            abstract: "A subcommand")

        func run() throws {
            // Do something
        }
    }
}

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
            } else if argument == "-version" {
                action = PrintVersionAction()
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

        if action == nil && files.isEmpty {
            print("skip \(skipVersion): no input files")
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
        // running on: [SkipSyntax.Source.File(path: "/opt/src/github/skiptools/Skip/Sources/SkipFoundationKip/Kip.swift")]
        //print("running on: \(sourceFiles)")

        // the token that signfies this is a skip-source module; e.g., Sources/CrossFoundationKip/Kip.swift acts as a directive to assemble Sources/CrossFoundation/*.swift
        let kipNameToken = "Kip"

        // the presence of a "Kip.swift" file in a folder named "SomeModuleKip" means we want to transpile the "SomeModule" module
        if let kipFile = sourceFiles.first(where: { $0.name == kipNameToken + ".swift" }),
           let kipFolderURL = URL(fileURLWithPath: kipFile.path, isDirectory: false).deletingLastPathComponent() as URL?,
           kipFolderURL.path.hasSuffix(kipNameToken)  {
            let output = options.outputDirectory ?? NSTemporaryDirectory()

            let moduleName = String(kipFolderURL.lastPathComponent.dropLast(kipNameToken.count))

            do {
                let baseURL = URL(fileURLWithPath: kipFile.path, isDirectory: false)
                    .deletingLastPathComponent() // /opt/src/skipsource/Skip/Sources/SkipFoundationKip
                    .deletingLastPathComponent() // /opt/src/skipsource/Skip/Sources
                    .deletingLastPathComponent() // /opt/src/skipsource/Skip

                // TODO: handle tests vs. sources?
                let (root, files) = try await SkipAssembler.assemble(root: baseURL, moduleRootPath: "modules", sourceFolder: "Sources", testsFolder: nil, targets: SkipTargetSet(GradleTarget.lib(moduleName)), destRoot: "\(output)/skip/out/\(moduleName)/")
            } catch {
            }
        } else {
        for sourceFile in sourceFiles {
            let source = try Source(file: sourceFile)
            let syntaxTree = SyntaxTree(source: source, preprocessorSymbols: Set(options.preprocessorSymbols))
            let translator = KotlinTranslator(syntaxTree: syntaxTree)
            let kotlinTree = translator.translateSyntaxTree()
            kotlinTree.messages.forEach { print($0) }

            if let outputDir = options.outputDirectory {
                let outputFileURL = outputFileURL(for: sourceFile, in: URL(fileURLWithPath: outputDir))
                try "".write(to: outputFileURL, atomically: false, encoding: .utf8)
            }
        }
        }
    }

    /// Xcode requires that we create an output file in order for incremental build tools to work.
    ///
    /// - Warning: This is duplicated in SkippyTool.
    func outputFileURL(for sourceFile: Source.File, in outputDir: URL) -> URL {
        var outputFileName = sourceFile.name
        if outputFileName.hasSuffix(".swift") {
            outputFileName = String(outputFileName.dropLast(".swift".count))
        }
        outputFileName += "_skippy.swift"
        return outputDir.appendingPathComponent(outputFileName)
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

private struct PrintVersionAction: Action {
    func perform(on sourceFiles: [Source.File], options: Options) async throws {
        print("skip version \(skipVersion)")
    }
}
