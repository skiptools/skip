import Foundation
import SwiftParser
import SwiftSyntax

/// Manages the transpilation process.
public struct Transpiler {
    public let inputFiles: [String]

    /// Supply files to transpile. Only `.swift` files will be processed.
    public init(inputFiles: [String]) {
        self.inputFiles = inputFiles
    }

    /// Perform transpilation, feeding results to the given handler.
    public func transpile(handler: (Transpilation) throws -> Void) async throws {
        let transpilations = try await withThrowingTaskGroup(of: Transpilation.self) { group in
            for inputFile in inputFiles {
                guard inputFile.hasSuffix(".swift") else {
                    continue
                }
                let outputFile = String(inputFile.dropLast("swift".count)) + "kt"
                group.addTask {
                    let ast = try ast(for: inputFile)
                    return Transpilation(inputFile: inputFile, outputFile: outputFile, ast: ast)
                }
            }
            var transpilations: [Transpilation] = []
            for try await transpilation in group {
                transpilations.append(transpilation)
            }
            return transpilations
        }

        let analysis = try await Task {
            return try analyze(transpilations)
        }.value

        try await withThrowingTaskGroup(of: Void.self) { group in
            for transpilation in transpilations {
                group.addTask {
                    try transform(transpilation, analysis: analysis)
                    try generateCode(transpilation)
                }
            }
            try await group.waitForAll()
        }

        try transpilations.forEach { try handler($0) }
    }

    private func ast(for file: String) throws -> AST {
        return AST()
    }

    private func analyze(_ transpilations: [Transpilation]) throws -> Analysis {
        return Analysis()
    }

    private func transform(_ transpilation: Transpilation, analysis: Analysis) throws {
    }

    private func generateCode(_ transpilation: Transpilation) throws {
        //~~~
        transpilation.code = try String(contentsOfFile: transpilation.inputFile)
    }
}

public class Transpilation {
    public let inputFile: String
    public let outputFile: String

    init(inputFile: String, outputFile: String, ast: AST) {
        self.inputFile = inputFile
        self.outputFile = outputFile
        self.ast = ast
    }

    let ast: AST

    //~~~
    public var code = ""
}
