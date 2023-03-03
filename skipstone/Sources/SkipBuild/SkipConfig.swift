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
