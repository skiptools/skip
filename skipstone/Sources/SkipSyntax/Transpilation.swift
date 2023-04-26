/// A transpilation result.
public struct Transpilation : Encodable {
    public var sourceFile: Source.FilePath
    public var isSourceFileSynthetic = false
    public var output: Source
    public var outputMap: OutputMap = OutputMap(entries: [])
    public var messages: [Message] = []
    public var duration: Double = 0.0
}
