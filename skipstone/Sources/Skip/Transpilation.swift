/// A transpilation result.
public struct Transpilation {
    public let sourceFile: Source.File
    public let outputFile: Source.File
    public var outputContent = ""
    public var outputMap = OutputMap(entries: [])
    public var messages: [Message] = []
}
