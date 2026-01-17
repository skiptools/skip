// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// An entity that may have been parsed or translated from source.
protocol SourceDerived: AnyObject {
    var sourceFile: Source.FilePath? { get }
    var sourceRange: Source.Range? { get }

    /// Messages for this derivation.
    var messages: [Message] { get set }

    /// A more specific range to use for messages for this derivation.
    var messageSourceRange: Source.Range? { get }
}
