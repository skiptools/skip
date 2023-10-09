/// An entity that may have been parsed or translated from source.
protocol SourceDerived {
    var sourceFile: Source.FilePath? { get }
    var sourceRange: Source.Range? { get }

    /// Messages for this derivation.
    var messages: [Message] { get set }

    /// A more specific range to use for messages for this derivation.
    var messageSourceRange: Source.Range? { get }
}
