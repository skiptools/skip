// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Map output ranges to source ranges.
///
/// Note that a `Decodable` version of this structure exists as `SkipUnit.SourceMap`.
/// These types must maintain serialization compatibility.
public struct OutputMap : Encodable {
    public struct Entry : Encodable {
        let sourceFile: Source.FilePath
        let sourceRange: Source.Range?
        let range: Source.Range
    }

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
    public func source(of outputRange: Source.Range) -> (file: Source.FilePath, range: Source.Range?)? {
        // Use the last entry to include the given output range
        guard let entry = entries.last(where: { $0.range.start >= outputRange.start && $0.range.end >= outputRange.end }) else {
            return nil
        }
        return (file: entry.sourceFile, range: entry.sourceRange)
    }
}
