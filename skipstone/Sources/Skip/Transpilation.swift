/// A transpilation result.
public struct Transpilation {
    public let sourceFile: Source.File
    public let outputFile: Source.File
    public var outputContent = ""
    public var messages: [Message] = []
}
