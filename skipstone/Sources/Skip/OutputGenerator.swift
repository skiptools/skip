/// Generate output from a graph of nodes.
class OutputGenerator {
    /// Supply root nodes.
    init(roots: [OutputNode]) {

    }

    func generateOutput() -> (content: String, map: OutputMap) {
        return ("", OutputMap(entries: []))
    }

    func append(_ node: OutputNode, indentation: Indentation) {

    }

    func append(_ string: String) {

    }

    func append(_ convertible: CustomStringConvertible) {
        append(convertible.description)
    }
}

/// A node in the output graph.
protocol OutputNode {
    var sourceFile: Source.File? { get }
    var sourceRange: Source.Range? { get }

    /// Any leading trivia before the output. Trivia is not part of the ranges.
    func leadingTrivia(indentation: Indentation) -> String

    /// Append the content of this node to the given generator.
    func append(to output: OutputGenerator, indentation: Indentation)
}
