/// Map output ranges to source ranges.
public struct OutputMap {
    private let entries: [(sourceFile: Source.File, sourceRange: Source.Range?, range: Source.Range)]

    /// Supply entries mapping source ranges to output ranges.
    init(entries: [(sourceFile: Source.File, sourceRange: Source.Range?, range: Source.Range)]) {
        self.entries = entries.sorted { $0.range.start < $1.range.start }
    }

    /// Find the source information for the given output range.
    func source(of outputRange: Source.Range) -> (file: Source.File, range: Source.Range?)? {
        // Use the last entry to include the given output range
        guard let entry = entries.last(where: { $0.range.start >= outputRange.start && $0.range.end >= outputRange.end }) else {
            return nil
        }
        return (file: entry.sourceFile, range: entry.sourceRange)
    }
}
