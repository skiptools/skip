/// An entity that may have been parsed or translated from source.
protocol SourceDerived {
    var sourceFile: Source.File? { get }
    var sourceRange: Source.Range? { get }

    /// Messages for this derivation.
    var messages: [Message] { get set }
}

