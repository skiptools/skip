/// Map output ranges to source ranges.
public struct OutputMap {
    public typealias Entry = (sourceFile: Source.File, sourceRange: Source.Range?, range: Source.Range)
    private let entries: [Entry]

    /// Supply entries mapping source ranges to output ranges.
    public init(entries: [Entry]) {
        // Sort by start and then from longest to shortest (i.e. reverse by end).
        // Thus the last entry to contain a range will be the most specific
        self.entries = entries.sorted {
            $0.range.start < $1.range.start || ($0.range.start == $1.range.start && $0.range.end > $1.range.end)
        }
    }

    /// Find the source information for the given output range.
    public func source(of outputRange: Source.Range) -> (file: Source.File, range: Source.Range?)? {
        // Use the last entry to include the given output range
        guard let entry = entries.last(where: { $0.range.start >= outputRange.start && $0.range.end >= outputRange.end }) else {
            return nil
        }
        return (file: entry.sourceFile, range: entry.sourceRange)
    }
}
