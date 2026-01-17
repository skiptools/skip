// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// A node in the Kotlin syntax tree.
///
/// Kotlin nodes are generally mutable.
class KotlinSyntaxNode: SourceDerived, OutputNode {
    let nodeName: String
    let sourceFile: Source.FilePath?
    let sourceRange: Source.Range?

    init(nodeName: String, sourceFile: Source.FilePath? = nil, sourceRange: Source.Range? = nil) {
        self.nodeName = nodeName
        self.sourceFile = sourceFile
        self.sourceRange = sourceRange
    }

    /// Visit this node and its children depth first, performing the given action.
    ///
    /// - Parameters:
    ///   - ifSkipBlockContent: Whether to only visit content within `#if SKIP`
    ///   - perform: The action to perform.
    func visit(ifSkipBlockContent: Bool = false, perform: (KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode>) {
        if ifSkipBlockContent {
            // For top-level invocation on some node, look to see if it is in `#if SKIP` up the chain
            if (self as? KotlinStatement)?.isInIfSkipBlock == true {
                visit(perform: perform)
            } else {
                for child in children {
                    // For downstream checks, just look for the start of the `#if SKIP` block
                    child.visitIfStartSkipBlockContent(perform: perform)
                }
            }
        } else if case .recurse(let onLeave) = perform(self) {
            for child in children {
                child.visit(perform: perform)
            }
            if let onLeave {
                onLeave(self)
            }
        }
    }

    private func visitIfStartSkipBlockContent(perform: (KotlinSyntaxNode) -> VisitResult<KotlinSyntaxNode>) {
        if (self as? KotlinStatement)?.extras?.isIfSkipBlock() == true {
            visit(perform: perform)
        } else {
            for child in children {
                child.visitIfStartSkipBlockContent(perform: perform)
            }
        }
    }

    /// Insert any non-standard dependencies required by this node.
    func insertDependencies(into dependencies: inout KotlinDependencies) {
    }

    weak var parent: KotlinSyntaxNode?
    var children: [KotlinSyntaxNode] {
        return []
    }

    /// Assign parent references below this node.
    final func assignParentReferences() {
        for child in children {
            child.parent = self
            child.assignParentReferences()
        }
    }

    /// Find the nearest type declaration by traversing up the syntax tree.
    final var owningTypeDeclaration: KotlinStatement? {
        var current: KotlinSyntaxNode? = self
        while current != nil {
            if current is KotlinClassDeclaration || current is KotlinInterfaceDeclaration {
                return current as? KotlinStatement
            }
            current = current?.parent
        }
        return nil
    }

    /// Whether this node is within an `#if SKIP` block in the source.
    final var isInIfSkipBlock: Bool {
        var node: KotlinSyntaxNode? = self
        while node != nil {
            if (node as? KotlinStatement)?.extras?.isIfSkipBlock() == true {
                return true
            }
            node = node?.parent
        }
        return false
    }

    var messages: [Message] = []

    /// All messages rooted in this subtree.
    var subtreeMessages: [Message] {
        return messages + children.flatMap { $0.subtreeMessages }
    }

    public var messageSourceRange: Source.Range? {
        return nil
    }

    func leadingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func trailingTrivia(indentation: Indentation) -> String {
        return ""
    }

    func append(to output: OutputGenerator, indentation: Indentation) {
    }
}
