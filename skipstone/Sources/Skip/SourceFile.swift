import Foundation

/// A Swift source file.
public struct SourceFile {
    public let path: String

    public init?(path: String) {
        guard path.hasSuffix(".swift") && path.count > ".swift".count else {
            return nil
        }
        self.path = path
    }

    public var outputPath: String {
        return path.dropLast(".swift".count) + ".kt"
    }

    public var content: String {
        get throws {
            return try String(contentsOfFile: path)
        }
    }
}
