import Foundation

/// A contents of a `skip.yml` config file
struct SkipConfig : Codable {
    
    var skip: TranspilationConfig?

    /// The rules to build up the `build.gradle.kts` file
    var build: GradleBlock?

    /// The rules to build up a `settings.gradle.kts` file
    var settings: GradleBlock?
}

struct TranspilationConfig : Codable {
    /// The name of the package this module should be set to
    var package: String?
}
