// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Indentation helper.
public struct Indentation: ExpressibleByIntegerLiteral, CustomStringConvertible {
    public static let zero = Indentation(level: 0)

    public let level: Int

    public init(level: Int) {
        self.level = level
    }

    public init(integerLiteral: Int) {
        self.level = integerLiteral
    }

    public func inc() -> Indentation {
        return Indentation(level: level + 1)
    }

    public func dec() -> Indentation {
        return Indentation(level: max(0, level - 1))
    }

    public var description: String {
        return String(repeating: "    ", count: level)
    }
}

extension Array where Element == String {
    public mutating func append(_ indentation: Indentation, _ value: String) {
        self.append(indentation.description + value)
    }

    public mutating func append(_ indentation: Indentation, _ value: [String]) {
        value.forEach { append(indentation, $0) }
    }
}
