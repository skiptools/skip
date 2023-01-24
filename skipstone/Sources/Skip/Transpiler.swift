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
    public func transpile(handler: (Transpilation) throws -> Void) throws {
        for inputFile in inputFiles {
            guard inputFile.hasSuffix(".swift") else {
                continue
            }
            let outputFile = String(inputFile.dropLast("swift".count)) + "kt"
            var transpilation = Transpilation(inputFile: inputFile, outputFile: outputFile)
            transpilation.code = try String(contentsOfFile: inputFile)
            try handler(transpilation)
        }
    }
}

public struct Transpilation {
    public let inputFile: String
    public let outputFile: String
    public var code = ""
}
