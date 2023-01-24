/// A transpilation result.
public struct Transpilation {
    public let sourceFile: Source.File
    public var messages: [Message] = []
    public var outputContent = ""
}
