import Foundation

/// A contents of a `skip.json` (or `skip.yml`) file.
public struct SkipConfig : Decodable {
    /// The version of the skip config format, defaulting to 1
    public var version: Version
    public enum Version : Int, Decodable {
        case v1 = 1
    }

    /// The directory pattern of sub-module folders to scan
    /// Example: modules: ["Sources/*Kotlin"]
    public var modules: [String]?

    public var actions: [Action]?

    public struct Action : Decodable {
        /// An identifier, in case an action needs to be referenced from another action
        public var id: String?

        /// The name of the action, for logging and debugging purposes
        public var name: String?

        /// An expression to match against the path of the candidate file.
        ///
        /// Defaults to `.*.kt`
        public var include: [String]?

        /// An expression to match against the path of the candidate file.
        ///
        /// Defaults to none.
        public var exclude: [String]?

        /// One or more regular expressions run on the input Swift file before transpile
        public var prereplace: [String]?

        /// One or more regular expressions run on the output Kotlin file after transpile
        public var postreplace: [String]?
    }
}

/// The target mode for generating Gradle config
public enum GradleTarget {
    /// An app module target
    case app(String)
    /// A library module target
    case lib(String)

    public var moduleName: String {
        switch self {
        case .app(let moduleName): return moduleName
        case .lib(let moduleName): return moduleName
        }
    }

    var pluginType: String {
        switch self {
        case .app: return "com.android.application"
        case .lib: return "com.android.library"
        }
    }

    var isApp: Bool {
        switch self {
        case .app: return true
        case .lib: return false
        }
    }

    var isLibrary: Bool {
        switch self {
        case .app: return false
        case .lib: return true
        }
    }
}


