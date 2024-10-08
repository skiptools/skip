import Foundation

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
    /// Skip mode: kotlin|swift
    var mode: String?
}


struct SkipToolchain : Equatable, Codable {
    var architectures: [SkipArchitecture]?
}

struct SkipArchitecture : Equatable, Codable {
    var arch: String
}

