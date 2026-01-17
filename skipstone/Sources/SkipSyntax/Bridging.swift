// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Determines what API is bridged without being explicitly annotated.
public enum AutoBridge: Int {
    /// Bridge only API with bridge attribute.
    case none
    /// Bridge UI code that isn't explicitly excluded.
    case `default`
    /// Bridge all internal or public API that isn't explicitly excluded.
    case `internal`
    /// Bridge all public API that isn't explicitly excluded.
    case `public`
}

/// Whether a declaration is briging.
func isBridging(attributes: Attributes, visibility: Modifiers.Visibility, bridgeMemberVisibility: Modifiers.Visibility?, autoBridge: AutoBridge) -> Bool {
    guard !attributes.isBridge else {
        return true
    }
    guard !attributes.isNoBridge && !attributes.contains(.unavailable) else {
        return false
    }
    if let bridgeMemberVisibility, visibility >= .public || visibility >= bridgeMemberVisibility {
        return true
    }
    guard autoBridge != .none && autoBridge != .default else {
        return false
    }
    return visibility >= .public || (autoBridge == .internal && visibility > .fileprivate)
}
