/// The result of visiting a syntax node.
enum VisitResult<N> {
    /// Skip the content of this node.
    case skip
    /// Recurse into the content of this node, optionally invoking the given block when leaving this node's content.
    case recurse(((N) -> Void)?)
}
