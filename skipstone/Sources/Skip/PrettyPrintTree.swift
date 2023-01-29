/// Structure for pretty printing tree content.
public struct PrettyPrintTree {
    let root: String
    let children: [PrettyPrintTree]

    init(root: String, children: [PrettyPrintTree] = []) {
        self.root = root
        self.children = children
    }
}

extension PrettyPrintTree: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = PrettyPrintTree(root: value)
    }
}

extension PrettyPrintTree: CustomStringConvertible {
    public var description: String {
        return description(prefix: "")
    }

    private func description(prefix: String, isLast: Bool = true) -> String {
        let rootLine = "\(prefix) \(root)\n"

        // If we're not the last sibling, continue our sibling line while printing our child nodes
        var childrenPrefix = prefix
        if !prefix.isEmpty {
            childrenPrefix = isLast ? prefix.dropLast(3) + "   " : prefix.dropLast(3) + " │ "
        }
        let childLines = children.enumerated()
            .map {
                let isLast = $0.offset >= children.count - 1
                let childPrefix = isLast ? " └─" : " ├─"
                return $0.element.description(prefix: childrenPrefix + childPrefix, isLast: isLast)
            }
            .joined(separator: "")
        return rootLine + childLines
    }
}

/// Entity that can generate a pretty print tree.
public protocol PrettyPrintable {
    var prettyPrintTree: PrettyPrintTree { get }
}
