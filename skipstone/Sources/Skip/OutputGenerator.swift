/// Generate output from a graph of nodes.
class OutputGenerator {
    private let roots: [OutputNode]
    private var content = ""
    private typealias MapEntryOffsets = (sourceFile: Source.File, sourceRange: Source.Range?, offset: Int, length: Int)
    private var mapEntryOffsets: [MapEntryOffsets] = []

    /// Supply root nodes.
    init(roots: [OutputNode]) {
        self.roots = roots
    }

    func generateOutput(file: Source.File) -> (output: Source, map: OutputMap) {
        roots.forEach { append($0, indentation: .zero) }
        let output = Source(file: file, content: content)
        let ret = (output, OutputMap(entries: mapEntryOffsets.map { outputMapEntry(for: $0, in: output) }))
        content = ""
        mapEntryOffsets.removeAll()
        return ret
    }

    func append(_ node: OutputNode, indentation: Indentation) {
        append(node.leadingTrivia(indentation: indentation))
        let startOffset = content.utf8.count
        node.append(to: self, indentation: indentation)
        let length = content.utf8.count - startOffset
        if length > 0, let sourceFile = node.sourceFile {
            mapEntryOffsets.append((sourceFile, node.sourceRange, startOffset, length))
        }
    }

    func append(_ string: String) {
        content += string
    }

    func append(_ convertible: CustomStringConvertible) {
        append(convertible.description)
    }

    private func outputMapEntry(for offsets: MapEntryOffsets, in output: Source) -> OutputMap.Entry {
        let range = output.range(offset: offsets.offset, length: offsets.length)
        return (sourceFile: offsets.sourceFile, sourceRange: offsets.sourceRange, range: range)
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
