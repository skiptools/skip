// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Universal

/// A contents of a `skip.yml` config file
struct SkipConfig : Codable {
    
    var skip: TranspilationConfig?

    /// The rules to build up the `build.gradle.kts` file
    var build: GradleBlock?

    /// The rules to build up a `settings.gradle.kts` file
    var settings: GradleBlock?

    /// The native toolchain info
    var toolchain: SkipToolchain?
}

struct TranspilationConfig : Codable {
    /// The name of the package this module should be set to
    var package: String?
    /// Skip mode: `native|transpiled`
    var mode: String?
    /// Whether/how to bridge this module
    var bridging: Either<Bool>.Or<BridgeConfig>?
    /// Namespace for code gen of dynamic types
    var dynamicroot: String?

    func isAutoBridgingEnabled() -> Bool {
        switch bridging {
        case .a(let enabled):
            return enabled
        case .b(let config):
            return config.auto == true || config.enabled == true
        case nil:
            return false
        }
    }

    func bridgingOptions() -> [String] {
        switch bridging {
        case .a:
            return []
        case .b(let config):
            switch config.options {
            case .a(let option):
                return [option]
            case .b(let options):
                return options
            case nil:
                return []
            }
        case nil:
            return []
        }
    }
}

struct SkipToolchain : Equatable, Codable {
    var architectures: [SkipArchitecture]?
}

struct SkipArchitecture : Equatable, Codable {
    var arch: String
}

struct BridgeConfig : Equatable, Codable {
    var enabled: Bool? /// Deprecated: use `auto`
    var auto: Bool?
    var options: Either<String>.Or<[String]>?
}

enum BridgeOption: String {
    case kotlincompat
}
