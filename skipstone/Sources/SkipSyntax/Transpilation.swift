/// A transpilation result.
public struct Transpilation : Encodable { // Encodable for tool JSON output option
    public var input: Source
    public var output: Source
    public var outputType: OutputType
    public var outputMap: OutputMap = OutputMap(entries: [])
    public var messages: [Message] = []
    public var duration: Double = 0.0
}
