// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Types of transpiler output.
public enum OutputType : Encodable { // Encodable for use in Transpilation
    /// Transpilation of source Swift.
    case `default`
    /// Swift generated to bridge a transpiled type to Swift.
    case bridgeToSwift
    /// Swift generated to bridge a native Swift type to the target language.
    case bridgeFromSwift
}
