/// A transpilation result.
public struct Transpilation {
    public let sourceFile: Source.File
    public var output: Source
    public var outputMap = OutputMap(entries: [])
    public var messages: [Message] = []
}
