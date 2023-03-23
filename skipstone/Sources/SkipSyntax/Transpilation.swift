/// A transpilation result.
public struct Transpilation : Encodable {
    public let sourceFile: Source.FilePath
    public var output: Source
    public var outputMap: OutputMap = OutputMap(entries: [])
    public var messages: [Message] = []
    public var duration: Double
}
