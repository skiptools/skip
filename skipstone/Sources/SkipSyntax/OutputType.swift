/// Types of transpiler output.
public enum OutputType : Encodable { // Encodable for use in Transpilation
    /// Transpilation of source Swift.
    case `default`
    /// Swift generated to bridge a transpiled type to Swift.
    case bridgeToSwift
    /// Swift generated to bridge a native Swift type to Kotlin.
    case bridgeToKotlin
}
