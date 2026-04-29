// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Generate output from a graph of nodes.
///
/// Uses an iterative approach with an explicit work stack to avoid stack overflow
/// on deeply nested AST trees (e.g., long SwiftUI modifier chains that produce
/// hundreds of levels of nesting).
///
/// Design: When a node's `append(to:indentation:)` method calls `output.append(child)`,
/// instead of recursing, the child is recorded as a pending fragment. After the node's
/// method returns, its recorded fragments are pushed onto the work stack. The main loop
/// then processes fragments iteratively: text fragments are appended directly to the
/// output buffer, and node fragments are expanded by running that node's append method
/// to produce more fragments — all without growing the call stack.
public final class OutputGenerator {
    private let root: OutputNode
    private typealias MapEntryOffsets = (sourceFile: Source.FilePath, sourceRange: Source.Range?, offset: Int, length: Int)
    private var mapEntryOffsets: [MapEntryOffsets] = []

    /// Fragments produced when a node's `append(to:)` runs in recording mode.
    /// Text fragments are literal string output. Node fragments are deferred child
    /// expansions. Begin/end markers track source mapping offsets around content.
    private enum Fragment {
        case text(String)
        case node(OutputNode, Indentation)
        case nodeCustom(OutputNode, Indentation, (OutputGenerator) -> Void)
        case beginNode(OutputNode)
        case endNode(OutputNode, Indentation)
    }

    /// Fragments accumulated during the current recording session.
    /// The public `append` methods always record fragments here; the work loop
    /// in `generateOutput` is responsible for processing them iteratively.
    private var recordedFragments: [Fragment] = []

    /// Supply node.
    init(root: OutputNode) {
        self.root = root
    }

    /// Run a node's append method to capture its output as fragments.
    ///
    /// The node's `append(to:indentation:)` (or custom closure) executes, but every call
    /// it makes to `output.append(...)` records a fragment rather than recursing or writing.
    /// The result is a flat list: [leadingTrivia, beginNode, ...childFragments..., endNode].
    private func recordNodeFragments(node: OutputNode, indentation: Indentation, customAppend: ((OutputGenerator) -> Void)? = nil) -> [Fragment] {
        // Save the outer recording buffer so re-entrant calls don't clobber it.
        let savedFragments = recordedFragments
        recordedFragments = []

        // Leading trivia.
        let leading = node.leadingTrivia(indentation: indentation)
        if !leading.isEmpty {
            recordedFragments.append(.text(leading))
        }

        // Source mapping begin marker.
        recordedFragments.append(.beginNode(node))

        // Run the node's append logic — all its output.append() calls record fragments.
        if let customAppend = customAppend {
            customAppend(self)
        } else {
            node.append(to: self, indentation: indentation)
        }

        // Source mapping end marker (handles trailing trivia and offset computation).
        recordedFragments.append(.endNode(node, indentation))

        let result = recordedFragments
        recordedFragments = savedFragments
        return result
    }

    func generateOutput(file: Source.FilePath) -> (output: Source, map: OutputMap) {
        var output = ""

        // Seed the work stack with the root node.
        var workStack: [Fragment] = [.node(root, .zero)]

        // Stack tracking source-mapping start offsets for nested beginNode/endNode pairs.
        var mappingStack: [Int] = []

        // Process fragments iteratively until the stack is empty.
        while let fragment = workStack.popLast() {
            switch fragment {
            case .text(let str):
                output += str

            case .node(let node, let indentation):
                // Expand this node: run its append(to:) in recording mode to get fragments,
                // then push them onto the work stack (reversed so first fragment pops first).
                let fragments = recordNodeFragments(node: node, indentation: indentation)
                workStack.append(contentsOf: fragments.reversed())

            case .nodeCustom(let node, let indentation, let customAppend):
                let fragments = recordNodeFragments(node: node, indentation: indentation, customAppend: customAppend)
                workStack.append(contentsOf: fragments.reversed())

            case .beginNode:
                // Record the current content offset for source mapping.
                mappingStack.append(output.utf8.count)

            case .endNode(let node, let indentation):
                // Compute trailing trivia and source mapping for this node.
                guard let startOffset = mappingStack.popLast() else { continue }
                let trailingTrivia = node.trailingTrivia(indentation: indentation)
                var trailingNewline = false
                if !trailingTrivia.isEmpty && output.last == "\n" {
                    output.removeLast()
                    trailingNewline = true
                }
                let length = output.utf8.count - startOffset
                if length > 0, let sourceFile = node.sourceFile {
                    mapEntryOffsets.append((sourceFile, node.sourceRange, startOffset, length))
                }
                if !trailingTrivia.isEmpty {
                    output += " "
                    output += trailingTrivia
                    if trailingNewline {
                        output += "\n"
                    }
                }
            }
        }

        let source = Source(file: file, content: output)
        let ret = (source, OutputMap(entries: mapEntryOffsets.map { outputMapEntry(for: $0, in: source) }))
        mapEntryOffsets.removeAll()
        return ret
    }


    // MARK: - Public API (called by OutputNode.append implementations)

    @discardableResult public func append(_ node: OutputNode, indentation: Indentation) -> OutputGenerator {
        recordedFragments.append(.node(node, indentation))
        return self
    }

    @discardableResult public func append(_ node: OutputNode, indentation: Indentation, appendContent: @escaping (OutputGenerator) -> Void) -> OutputGenerator {
        recordedFragments.append(.nodeCustom(node, indentation, appendContent))
        return self
    }

    @discardableResult public func append(_ nodes: [OutputNode], indentation: Indentation) -> OutputGenerator {
        for node in nodes {
            append(node, indentation: indentation)
        }
        return self
    }

    @discardableResult public func append(_ string: String) -> OutputGenerator {
        recordedFragments.append(.text(string))
        return self
    }

    @discardableResult public func append(_ convertible: CustomStringConvertible) -> OutputGenerator {
        append(convertible.description)
    }

    private func outputMapEntry(for offsets: MapEntryOffsets, in output: Source) -> OutputMap.Entry {
        let range = output.range(offset: offsets.offset, length: offsets.length)
        return OutputMap.Entry(sourceFile: offsets.sourceFile, sourceRange: offsets.sourceRange, range: range)
    }
}

/// A node in the output graph.
public protocol OutputNode {
    var sourceFile: Source.FilePath? { get }
    var sourceRange: Source.Range? { get }

    /// Any leading trivia before the output. Trivia is not part of the ranges.
    func leadingTrivia(indentation: Indentation) -> String

    /// Append the content of this node to the given generator.
    func append(to output: OutputGenerator, indentation: Indentation)

    /// Any trailing trivia after the output. Trivia is not part of the ranges.
    func trailingTrivia(indentation: Indentation) -> String
}
