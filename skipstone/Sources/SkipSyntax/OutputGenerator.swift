/// Generate output from a graph of nodes.
final class OutputGenerator {
    private let root: OutputNode
    private var content = ""
    private typealias MapEntryOffsets = (sourceFile: Source.FilePath, sourceRange: Source.Range?, offset: Int, length: Int)
    private var mapEntryOffsets: [MapEntryOffsets] = []

    /// Supply node.
    init(root: OutputNode) {
        self.root = root
    }

    func generateOutput(file: Source.FilePath) -> (output: Source, map: OutputMap) {
        append(root, indentation: .zero)
        let output = Source(file: file, content: content)
        let ret = (output, OutputMap(entries: mapEntryOffsets.map { outputMapEntry(for: $0, in: output) }))
        content = ""
        mapEntryOffsets.removeAll()
        return ret
    }

    @discardableResult func append(_ node: OutputNode, indentation: Indentation) -> OutputGenerator {
        return append(node, indentation: indentation) {
            node.append(to: $0, indentation: indentation)
        }
    }

    @discardableResult func append(_ node: OutputNode, indentation: Indentation, appendContent: (OutputGenerator) -> Void) -> OutputGenerator {
        append(node.leadingTrivia(indentation: indentation))
        let startOffset = content.utf8.count
        appendContent(self)
        let trailingTrivia = node.trailingTrivia(indentation: indentation)
        var trailingNewline = false
        if !trailingTrivia.isEmpty && content.last == "\n" {
            content = String(content.dropLast())
            trailingNewline = true
        }
        let length = content.utf8.count - startOffset
        if length > 0, let sourceFile = node.sourceFile {
            mapEntryOffsets.append((sourceFile, node.sourceRange, startOffset, length))
        }
        if !trailingTrivia.isEmpty {
            content += " \(trailingTrivia)"
            if trailingNewline {
                content += "\n"
            }
        }
        return self
    }

    @discardableResult func append(_ nodes: [OutputNode], indentation: Indentation) -> OutputGenerator {
        nodes.forEach { append($0, indentation: indentation) }
        return self
    }

    @discardableResult func append(_ string: String) -> OutputGenerator {
        content += string
        return self
    }

    @discardableResult func append(_ convertible: CustomStringConvertible) -> OutputGenerator {
        append(convertible.description)
        return self
    }

    private func outputMapEntry(for offsets: MapEntryOffsets, in output: Source) -> OutputMap.Entry {
        let range = output.range(offset: offsets.offset, length: offsets.length)
        return OutputMap.Entry(sourceFile: offsets.sourceFile, sourceRange: offsets.sourceRange, range: range)
    }
}

/// A node in the output graph.
protocol OutputNode {
    var sourceFile: Source.FilePath? { get }
    var sourceRange: Source.Range? { get }

    /// Any leading trivia before the output. Trivia is not part of the ranges.
    func leadingTrivia(indentation: Indentation) -> String

    /// Append the content of this node to the given generator.
    func append(to output: OutputGenerator, indentation: Indentation)

    /// Any trailing trivia after the output. Trivia is not part of the ranges.
    func trailingTrivia(indentation: Indentation) -> String
}
