//@_exported import SkipSource

@main struct SkipCommand {
    static func main() async throws {
        print("HELLO SKIPCLI")
    }
}

public struct skip {
    public private(set) var text = "Hello, World!"

    public init() {
//        let x = \SkipSource.SkipSwift.version
    }
}
