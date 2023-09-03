// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
extension Process {
    /// An async stream of standard out + err data resulting from process execution
    public typealias AsyncDataOutput = AsyncThrowingStream<Data, Swift.Error>

    /// An async stream of standard out + err lines resulting from process execution
    public typealias AsyncLineOutput = AsyncCompactMapSequence<AsyncDataOutput, String>

    /// Static function for exit handling that will only accept an exit code of 0
    public static func expectZeroExitCode(result: ProcessResult) throws {
        guard case .terminated(let code) = result.exitStatus else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
        if code != 0 {
            throw ProcessResult.Error.nonZeroExit(result)
        }
    }

    /// Forks the given command and returns an async stream of lines of output
    public static func streamLines(command arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment, workingDirectory: URL? = nil, onExit: @escaping (_ result: ProcessResult) throws -> ()) -> AsyncLineOutput {
        streamSeparator(command: arguments, environment: environment, workingDirectory: workingDirectory, onExit: onExit)
            .compactMap({ String(data: $0, encoding: .utf8) })
    }

    /// Forks the given command and returns an async stream of parsed JSON messages, one dictionary for each line of output.
    public static func streamJSON(command arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment, workingDirectory: URL? = nil, onExit: @escaping (_ result: ProcessResult) throws -> ()) -> AsyncThrowingCompactMapSequence<AsyncDataOutput, NSDictionary> {
        streamSeparator(command: arguments, environment: environment, workingDirectory: workingDirectory, onExit: onExit)
            .compactMap({ line in
                try JSONSerialization.jsonObject(with: line) as? NSDictionary
            })
    }


    /// Invokes the given command arguments and returns an async stream of output chunks delimited by the given separator (typically a newline).
    private static func streamSeparator(character separatorCharacter: UnicodeScalar = Character("\n").unicodeScalars.first!, command arguments: [String], environment: [String: String], workingDirectory: URL?, onExit: @escaping (_ result: ProcessResult) throws -> ()) -> AsyncDataOutput {
        AsyncThrowingStream { continuation in
            var buffer: [UInt8] = []
            func handleProcessOutput(err: Bool) -> (_ data: [UInt8]) -> Void {
                { outputBytes in
                    var data: ArraySlice<UInt8> = outputBytes[outputBytes.startIndex...] // turn array into slice
                    while let nl = data.firstIndex(of: separatorCharacter.utf8.first!) {
                        let line = buffer + data[data.startIndex..<nl]
                        continuation.yield(Data(line))
                        data = data[nl...].dropFirst() // continue processing the rest of the buffer
                        buffer = []
                    }
                    buffer += data
                }
            }

            let p = Process(arguments: arguments, environment: environment, workingDirectory: workingDirectory, outputRedirection: .stream(stdout: handleProcessOutput(err: false), stderr: handleProcessOutput(err: true), redirectStderr: true), loggingHandler: nil)

            do {
                try p.launch()
                p.waitUntilExit({ result in
                    switch result {
                    case .failure(let error):
                        continuation.finish(throwing: error)
                    case .success(let result):
                        if case .terminated = result.exitStatus {
                            do {
                                try onExit(result) // check the exit handler, which may throw is the exit code is non-zero
                                continuation.finish()
                            } catch {
                                continuation.finish(throwing: error)
                            }
                        } else {
                            continuation.finish(throwing: ProcessResult.Error.nonZeroExit(result))
                        }
                    }
                })
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

extension URL {
    /// The system temporary folder
    public static let tmpdir: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
}

extension FileManager {
    /// Creates a temporary folder with the given base name
    public func createTmpDir(in tmpDir: URL = .tmpdir, folder: String = UUID().uuidString, name: String) throws -> URL {
        let url = URL(fileURLWithPath: name, isDirectory: true, relativeTo: URL(fileURLWithPath: folder, isDirectory: true, relativeTo: tmpDir))
        try createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension ProcessInfo {
        /// The unique host identifier as returned from `IOPlatformExpertDevice` on Darwin and the contents of "/etc/machine-id" on Linux
    public var hostIdentifier: String? {
        #if canImport(IOKit)
        let matchingDict = IOServiceMatching("IOPlatformExpertDevice")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDict)
        defer { IOObjectRelease(service) }
        guard service != .zero else { return nil }
        return (IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, .zero).takeRetainedValue() as? String)
        #elseif os(Linux)
        return (try? String(contentsOfFile: "/etc/machine-id")) ?? (try? String(contentsOfFile: "/var/lib/dbus/machine-id"))
        #elseif os(Windows)
        // TODO: Windows registry key `MachineGuid`
        return nil
        #else
        return nil // unsupported platform
        #endif
    }
}

// MARK: cherry-picking swift-tools-support-core


/*
 This source file is part of the Swift.org open source project
 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception
 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

/// A struct representing a semver version.
public struct Version: Sendable {

    /// The major version.
    public let major: Int

    /// The minor version.
    public let minor: Int

    /// The patch version.
    public let patch: Int

    /// The pre-release identifier.
    public let prereleaseIdentifiers: [String]

    /// The build metadata.
    public let buildMetadataIdentifiers: [String]

    /// Creates a version object.
    public init(
        _ major: Int,
        _ minor: Int,
        _ patch: Int,
        prereleaseIdentifiers: [String] = [],
        buildMetadataIdentifiers: [String] = []
    ) {
        precondition(major >= 0 && minor >= 0 && patch >= 0, "Negative versioning is invalid.")
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prereleaseIdentifiers
        self.buildMetadataIdentifiers = buildMetadataIdentifiers
    }
}

/// An error that occurs during the creation of a version.
public enum VersionError: Error, CustomStringConvertible {
    /// The version string contains non-ASCII characters.
    /// - Parameter versionString: The version string.
    case nonASCIIVersionString(_ versionString: String)
    /// The version core contains an invalid number of Identifiers.
    /// - Parameters:
    ///   - identifiers: The version core identifiers in the version string.
    ///   - usesLenientParsing: A Boolean value indicating whether or not the lenient parsing mode was enabled when this error occurred.
    case invalidVersionCoreIdentifiersCount(_ identifiers: [String], usesLenientParsing: Bool)
    /// Some or all of the version core identifiers contain non-numerical characters or are empty.
    /// - Parameter identifiers: The version core identifiers in the version string.
    case nonNumericalOrEmptyVersionCoreIdentifiers(_ identifiers: [String])
    /// Some or all of the pre-release identifiers contain characters other than alpha-numerics and hyphens.
    /// - Parameter identifiers: The pre-release identifiers in the version string.
    case nonAlphaNumerHyphenalPrereleaseIdentifiers(_ identifiers: [String])
    /// Some or all of the build metadata identifiers contain characters other than alpha-numerics and hyphens.
    /// - Parameter identifiers: The build metadata identifiers in the version string.
    case nonAlphaNumerHyphenalBuildMetadataIdentifiers(_ identifiers: [String])

    public var description: String {
        switch self {
        case let .nonASCIIVersionString(versionString):
            return "non-ASCII characters in version string '\(versionString)'"
        case let .invalidVersionCoreIdentifiersCount(identifiers, usesLenientParsing):
            return "\(identifiers.count > 3 ? "more than 3" : "fewer than \(usesLenientParsing ? 2 : 3)") identifiers in version core '\(identifiers.joined(separator: "."))'"
        case let .nonNumericalOrEmptyVersionCoreIdentifiers(identifiers):
            if !identifiers.allSatisfy( { !$0.isEmpty } ) {
                return "empty identifiers in version core '\(identifiers.joined(separator: "."))'"
            } else {
                // Not checking for `.isASCII` here because non-ASCII characters should've already been caught before this.
                let nonNumericalIdentifiers = identifiers.filter { !$0.allSatisfy(\.isNumber) }
                return "non-numerical characters in version core identifier\(nonNumericalIdentifiers.count > 1 ? "s" : "") \(nonNumericalIdentifiers.map { "'\($0)'" } .joined(separator: ", "))"
            }
        case let .nonAlphaNumerHyphenalPrereleaseIdentifiers(identifiers):
            // Not checking for `.isASCII` here because non-ASCII characters should've already been caught before this.
            let nonAlphaNumericalIdentifiers = identifiers.filter { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
            return "characters other than alpha-numerics and hyphens in pre-release identifier\(nonAlphaNumericalIdentifiers.count > 1 ? "s" : "") \(nonAlphaNumericalIdentifiers.map { "'\($0)'" } .joined(separator: ", "))"
        case let .nonAlphaNumerHyphenalBuildMetadataIdentifiers(identifiers):
            // Not checking for `.isASCII` here because non-ASCII characters should've already been caught before this.
            let nonAlphaNumericalIdentifiers = identifiers.filter { !$0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
            return "characters other than alpha-numerics and hyphens in build metadata identifier\(nonAlphaNumericalIdentifiers.count > 1 ? "s" : "") \(nonAlphaNumericalIdentifiers.map { "'\($0)'" } .joined(separator: ", "))"
        }
    }
}

extension Version {
    // TODO: Rename this function to `init(string:usesLenientParsing:) throws`, after `init?(string: String)` is removed.
    // TODO: Find a better error-checking order.
    // Currently, if a version string is "forty-two", this initializer throws an error that says "forty" is only 1 version core identifier, which is not enough.
    // But this is misleading the user to consider "forty" as a valid version core identifier.
    // We should find a way to check for (or throw) "wrong characters used" errors first, but without overly-complicating the logic.
    /// Creates a version from the given string.
    /// - Parameters:
    ///   - versionString: The string to create the version from.
    ///   - usesLenientParsing: A Boolean value indicating whether or not the version string should be parsed leniently. If `true`, then the patch version is assumed to be `0` if it's not provided in the version string; otherwise, the parsing strictly follows the Semantic Versioning 2.0.0 rules. This value defaults to `false`.
    /// - Throws: A `VersionError` instance if the `versionString` doesn't follow [SemVer 2.0.0](https://semver.org).
    public init(versionString: String, usesLenientParsing: Bool = false) throws {
        // SemVer 2.0.0 allows only ASCII alphanumerical characters and "-" in the version string, except for "." and "+" as delimiters. ("-" is used as a delimiter between the version core and pre-release identifiers, but it's allowed within pre-release and metadata identifiers as well.)
        // Alphanumerics check will come later, after each identifier is split out (i.e. after the delimiters are removed).
        guard versionString.allSatisfy(\.isASCII) else {
            throw VersionError.nonASCIIVersionString(versionString)
        }

        let metadataDelimiterIndex = versionString.firstIndex(of: "+")
        // SemVer 2.0.0 requires that pre-release identifiers come before build metadata identifiers
        let prereleaseDelimiterIndex = versionString[..<(metadataDelimiterIndex ?? versionString.endIndex)].firstIndex(of: "-")

        let versionCore = versionString[..<(prereleaseDelimiterIndex ?? metadataDelimiterIndex ?? versionString.endIndex)]
        let versionCoreIdentifiers = versionCore.split(separator: ".", omittingEmptySubsequences: false)

        guard versionCoreIdentifiers.count == 3 || (usesLenientParsing && versionCoreIdentifiers.count == 2) else {
            throw VersionError.invalidVersionCoreIdentifiersCount(versionCoreIdentifiers.map { String($0) }, usesLenientParsing: usesLenientParsing)
        }

        guard
            // Major, minor, and patch versions must be ASCII numbers, according to the semantic versioning standard.
            // Converting each identifier from a substring to an integer doubles as checking if the identifiers have non-numeric characters.
            let major = Int(versionCoreIdentifiers[0]),
            let minor = Int(versionCoreIdentifiers[1]),
            let patch = usesLenientParsing && versionCoreIdentifiers.count == 2 ? 0 : Int(versionCoreIdentifiers[2])
        else {
            throw VersionError.nonNumericalOrEmptyVersionCoreIdentifiers(versionCoreIdentifiers.map { String($0) })
        }

        self.major = major
        self.minor = minor
        self.patch = patch

        if let prereleaseDelimiterIndex = prereleaseDelimiterIndex {
            let prereleaseStartIndex = versionString.index(after: prereleaseDelimiterIndex)
            let prereleaseIdentifiers = versionString[prereleaseStartIndex..<(metadataDelimiterIndex ?? versionString.endIndex)].split(separator: ".", omittingEmptySubsequences: false)
            guard prereleaseIdentifiers.allSatisfy( { $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) } ) else {
                throw VersionError.nonAlphaNumerHyphenalPrereleaseIdentifiers(prereleaseIdentifiers.map { String($0) })
            }
            self.prereleaseIdentifiers = prereleaseIdentifiers.map { String($0) }
        } else {
            self.prereleaseIdentifiers = []
        }

        if let metadataDelimiterIndex = metadataDelimiterIndex {
            let metadataStartIndex = versionString.index(after: metadataDelimiterIndex)
            let buildMetadataIdentifiers = versionString[metadataStartIndex...].split(separator: ".", omittingEmptySubsequences: false)
            guard buildMetadataIdentifiers.allSatisfy( { $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) } ) else {
                throw VersionError.nonAlphaNumerHyphenalBuildMetadataIdentifiers(buildMetadataIdentifiers.map { String($0) })
            }
            self.buildMetadataIdentifiers = buildMetadataIdentifiers.map { String($0) }
        } else {
            self.buildMetadataIdentifiers = []
        }
    }
}

extension Version: Comparable, Hashable {

    func isEqualWithoutPrerelease(_ other: Version) -> Bool {
        return major == other.major && minor == other.minor && patch == other.patch
    }

    // Although `Comparable` inherits from `Equatable`, it does not provide a new default implementation of `==`, but instead uses `Equatable`'s default synthesised implementation. The compiler-synthesised `==`` is composed of [member-wise comparisons](https://github.com/apple/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md#implementation-details), which leads to a false `false` when 2 semantic versions differ by only their build metadata identifiers, contradicting SemVer 2.0.0's [comparison rules](https://semver.org/#spec-item-10).
    @inlinable
    public static func == (lhs: Version, rhs: Version) -> Bool {
        !(lhs < rhs) && !(lhs > rhs)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let lhsComparators = [lhs.major, lhs.minor, lhs.patch]
        let rhsComparators = [rhs.major, rhs.minor, rhs.patch]

        if lhsComparators != rhsComparators {
            return lhsComparators.lexicographicallyPrecedes(rhsComparators)
        }

        guard lhs.prereleaseIdentifiers.count > 0 else {
            return false // Non-prerelease lhs >= potentially prerelease rhs
        }

        guard rhs.prereleaseIdentifiers.count > 0 else {
            return true // Prerelease lhs < non-prerelease rhs
        }

        for (lhsPrereleaseIdentifier, rhsPrereleaseIdentifier) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if lhsPrereleaseIdentifier == rhsPrereleaseIdentifier {
                continue
            }

            // Check if either of the 2 pre-release identifiers is numeric.
            let lhsNumericPrereleaseIdentifier = Int(lhsPrereleaseIdentifier)
            let rhsNumericPrereleaseIdentifier = Int(rhsPrereleaseIdentifier)

            if let lhsNumericPrereleaseIdentifier = lhsNumericPrereleaseIdentifier,
               let rhsNumericPrereleaseIdentifier = rhsNumericPrereleaseIdentifier {
                return lhsNumericPrereleaseIdentifier < rhsNumericPrereleaseIdentifier
            } else if lhsNumericPrereleaseIdentifier != nil {
                return true // numeric pre-release < non-numeric pre-release
            } else if rhsNumericPrereleaseIdentifier != nil {
                return false // non-numeric pre-release > numeric pre-release
            } else {
                return lhsPrereleaseIdentifier < rhsPrereleaseIdentifier
            }
        }

        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }

    // Custom `Equatable` conformance leads to custom `Hashable` conformance.
    // [SR-11588](https://bugs.swift.org/browse/SR-11588)
    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prereleaseIdentifiers)
    }
}

extension Version: CustomStringConvertible {
    public var description: String {
        var base = "\(major).\(minor).\(patch)"
        if !prereleaseIdentifiers.isEmpty {
            base += "-" + prereleaseIdentifiers.joined(separator: ".")
        }
        if !buildMetadataIdentifiers.isEmpty {
            base += "+" + buildMetadataIdentifiers.joined(separator: ".")
        }
        return base
    }
}

extension Version: LosslessStringConvertible {
    /// Initializes a version struct with the provided version string.
    /// - Parameter version: A version string to use for creating a new version struct.
    public init?(_ versionString: String) {
        try? self.init(versionString: versionString)
    }
}

extension Version {
    // This initialiser is no longer necessary, but kept around for source compatibility with SwiftPM.
    /// Create a version object from string.
    /// - Parameter  string: The string to parse.
    @available(*, deprecated, renamed: "init(_:)")
    public init?(string: String) {
        self.init(string)
    }
}

extension Version: ExpressibleByStringLiteral {

    public init(stringLiteral value: String) {
        guard let version = Version(value) else {
            fatalError("\(value) is not a valid version")
        }
        self = version
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }

    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
}

extension Version: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        guard let version = Version(string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid version string \(string)"))
        }

        self = version
    }
}

// MARK:- Range operations
extension ClosedRange where Bound == Version {
    /// Marked as unavailable because we have custom rules for contains.
    public func contains(_ element: Version) -> Bool {
        // Unfortunately, we can't use unavailable here.
        fatalError("contains(_:) is unavailable, use contains(version:)")
    }
}

// Disabled because compiler hits an assertion https://bugs.swift.org/browse/SR-5014
#if false
extension CountableRange where Bound == Version {
    /// Marked as unavailable because we have custom rules for contains.
    public func contains(_ element: Version) -> Bool {
        // Unfortunately, we can't use unavailable here.
        fatalError("contains(_:) is unavailable, use contains(version:)")
    }
}
#endif

extension Range where Bound == Version {
    /// Marked as unavailable because we have custom rules for contains.
    public func contains(_ element: Version) -> Bool {
        // Unfortunately, we can't use unavailable here.
        fatalError("contains(_:) is unavailable, use contains(version:)")
    }
}

extension Range where Bound == Version {
    public func contains(version: Version) -> Bool {
        // Special cases if version contains prerelease identifiers.
        if !version.prereleaseIdentifiers.isEmpty {
            // If the range does not contain prerelease identifiers, return false.
            if lowerBound.prereleaseIdentifiers.isEmpty && upperBound.prereleaseIdentifiers.isEmpty {
                return false
            }

            // At this point, one of the bounds contains prerelease identifiers.
            //
            // Reject 2.0.0-alpha when upper bound is 2.0.0.
            if upperBound.prereleaseIdentifiers.isEmpty && upperBound.isEqualWithoutPrerelease(version) {
                return false
            }
        }

        if lowerBound == version {
            return true
        }

        // Otherwise, apply normal contains rules.
        return version >= lowerBound && version < upperBound
    }
}

/// Process allows spawning new subprocesses and working with them.
///
/// Note: This class is thread safe.
public final class Process {
    /// Errors when attempting to invoke a process
    public enum Error: Swift.Error, Sendable {
        /// The program requested to be executed cannot be found on the existing search paths, or is not executable.
        case missingExecutableProgram(program: String)

        /// The current OS does not support the workingDirectory API.
        case workingDirectoryNotSupported
    }

    public enum OutputRedirection {
        /// Do not redirect the output
        case none
        /// Collect stdout and stderr output and provide it back via ProcessResult object. If redirectStderr is true,
        /// stderr be redirected to stdout.
        case collect(redirectStderr: Bool)
        /// Stream stdout and stderr via the corresponding closures. If redirectStderr is true, stderr be redirected to
        /// stdout.
        case stream(stdout: OutputClosure, stderr: OutputClosure, redirectStderr: Bool)

        /// Default collect OutputRedirection that defaults to not redirect stderr. Provided for API compatibility.
        public static let collect: OutputRedirection = .collect(redirectStderr: false)

        /// Default stream OutputRedirection that defaults to not redirect stderr. Provided for API compatibility.
        public static func stream(stdout: @escaping OutputClosure, stderr: @escaping OutputClosure) -> Self {
            return .stream(stdout: stdout, stderr: stderr, redirectStderr: false)
        }

        public var redirectsOutput: Bool {
            switch self {
            case .none:
                return false
            case .collect, .stream:
                return true
            }
        }

        public var outputClosures: (stdoutClosure: OutputClosure, stderrClosure: OutputClosure)? {
            switch self {
            case let .stream(stdoutClosure, stderrClosure, _):
                return (stdoutClosure: stdoutClosure, stderrClosure: stderrClosure)
            case .collect, .none:
                return nil
            }
        }

        public var redirectStderr: Bool {
            switch self {
            case let .collect(redirectStderr):
                return redirectStderr
            case let .stream(_, _, redirectStderr):
                return redirectStderr
            default:
                return false
            }
        }
    }

    // process execution mutable state
    private enum State {
        case idle
        case readingOutput(sync: DispatchGroup)
        case outputReady(stdout: Result<[UInt8], Swift.Error>, stderr: Result<[UInt8], Swift.Error>)
        case complete(ProcessResult)
        case failed(Swift.Error)
    }

    /// Typealias for process id type.
#if !os(Windows)
    public typealias ProcessID = pid_t
#else
    public typealias ProcessID = DWORD
#endif

    /// Typealias for stdout/stderr output closure.
    public typealias OutputClosure = ([UInt8]) -> Void

    /// Typealias for logging handling closure
    public typealias LoggingHandler = (String) -> Void

    private static var _loggingHandler: LoggingHandler?
    private static let loggingHandlerLock = NSLock()

    /// Global logging handler. Use with care! preferably use instance level instead of setting one globally.
    public static var loggingHandler: LoggingHandler? {
        get {
            Self.loggingHandlerLock.withLock {
                self._loggingHandler
            }
        } set {
            Self.loggingHandlerLock.withLock {
                self._loggingHandler = newValue
            }
        }
    }

    // deprecated 2/2022, remove once client migrate to logging handler
    @available(*, deprecated)
    public static var verbose: Bool {
        get {
            Self.loggingHandler != nil
        } set {
            Self.loggingHandler = newValue ? Self.logToStdout: .none
        }
    }

    private var _loggingHandler: LoggingHandler?

    // the log and setter are only required to backward support verbose setter.
    // remove and make loggingHandler a let property once verbose is deprecated
    private let loggingHandlerLock = NSLock()
    public private(set) var loggingHandler: LoggingHandler? {
        get {
            self.loggingHandlerLock.withLock {
                self._loggingHandler
            }
        }
        set {
            self.loggingHandlerLock.withLock {
                self._loggingHandler = newValue
            }
        }
    }

    // deprecated 2/2022, remove once client migrate to logging handler
    // also simplify loggingHandler (see above) once this is removed
    @available(*, deprecated)
    public var verbose: Bool {
        get {
            self.loggingHandler != nil
        }
        set {
            self.loggingHandler = newValue ? Self.logToStdout : .none
        }
    }

    /// The arguments to execute.
    public let arguments: [String]

    /// The environment with which the process was executed.
    public let environment: [String: String]

    /// The path to the directory under which to run the process.
    public let workingDirectory: URL?

    /// The process id of the spawned process, available after the process is launched.
#if os(Windows)
    private var _process: Foundation.Process?
    public var processID: ProcessID {
        return DWORD(_process?.processIdentifier ?? 0)
    }
#else
    public private(set) var processID = ProcessID()
#endif

    // process execution mutable state
    private var state: State = .idle
    private let stateLock = NSLock()

    private static let sharedCompletionQueue = DispatchQueue(label: "org.swift.tools-support-core.process-completion")
    private var completionQueue = Process.sharedCompletionQueue

    /// The result of the process execution. Available after process is terminated.
    /// This will block while the process is awaiting result
    @available(*, deprecated, message: "use waitUntilExit instead")
    public var result: ProcessResult? {
        return self.stateLock.withLock {
            switch self.state {
            case .complete(let result):
                return result
            default:
                return nil
            }
        }
    }

    // ideally we would use the state for this, but we need to access it while the waitForExit is locking state
    private var _launched = false
    private let launchedLock = NSLock()

    public var launched: Bool {
        return self.launchedLock.withLock {
            return self._launched
        }
    }

    /// How process redirects its output.
    public let outputRedirection: OutputRedirection

    /// Indicates if a new progress group is created for the child process.
    private let startNewProcessGroup: Bool

    /// Cache of validated executables.
    ///
    /// Key: Executable name or path.
    /// Value: Path to the executable, if found.
    private static var validatedExecutablesMap = [String: URL?]()
    private static let validatedExecutablesMapLock = NSLock()

    /// Create a new process instance.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - workingDirectory: The path to the directory under which to run the process.
    ///   - outputRedirection: How process redirects its output. Default value is .collect.
    ///   - startNewProcessGroup: If true, a new progress group is created for the child making it
    ///     continue running even if the parent is killed or interrupted. Default value is true.
    ///   - loggingHandler: Handler for logging messages
    ///
    @available(macOS 10.15, *)
    public init(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL?,
        outputRedirection: OutputRedirection = .collect,
        startNewProcessGroup: Bool = true,
        loggingHandler: LoggingHandler? = .none
    ) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.outputRedirection = outputRedirection
        self.startNewProcessGroup = startNewProcessGroup
        self.loggingHandler = loggingHandler ?? Process.loggingHandler
    }

    // deprecated 2/2022
    @_disfavoredOverload
    @available(*, deprecated, message: "use version without verbosity flag")
    @available(macOS 10.15, *)
    public convenience init(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL,
        outputRedirection: OutputRedirection = .collect,
        verbose: Bool,
        startNewProcessGroup: Bool = true
    ) {
        self.init(
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            outputRedirection: outputRedirection,
            startNewProcessGroup: startNewProcessGroup,
            loggingHandler: verbose ? { message in
                stdoutStream <<< message <<< "\n"
                stdoutStream.flush()
            } : nil
        )
    }

    /// Create a new process instance.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - outputRedirection: How process redirects its output. Default value is .collect.
    ///   - verbose: If true, launch() will print the arguments of the subprocess before launching it.
    ///   - startNewProcessGroup: If true, a new progress group is created for the child making it
    ///     continue running even if the parent is killed or interrupted. Default value is true.
    ///   - loggingHandler: Handler for logging messages
    public init(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        outputRedirection: OutputRedirection = .collect,
        startNewProcessGroup: Bool = true,
        loggingHandler: LoggingHandler? = .none
    ) {
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = nil
        self.outputRedirection = outputRedirection
        self.startNewProcessGroup = startNewProcessGroup
        self.loggingHandler = loggingHandler ?? Process.loggingHandler
    }

    @_disfavoredOverload
    @available(*, deprecated, message: "use version without verbosity flag")
    public convenience init(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        outputRedirection: OutputRedirection = .collect,
        verbose: Bool = Process.verbose,
        startNewProcessGroup: Bool = true
    ) {
        self.init(
            arguments: arguments,
            environment: environment,
            outputRedirection: outputRedirection,
            startNewProcessGroup: startNewProcessGroup,
            loggingHandler: verbose ? Self.logToStdout : .none
        )
    }

    public convenience init(
        args: String...,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        outputRedirection: OutputRedirection = .collect,
        loggingHandler: LoggingHandler? = .none
    ) {
        self.init(
            arguments: args,
            environment: environment,
            outputRedirection: outputRedirection,
            loggingHandler: loggingHandler
        )
    }

    /// Launch the subprocess. Returns a WritableByteStream object that can be used to communicate to the process's
    /// stdin. If needed, the stream can be closed using the close() API. Otherwise, the stream will be closed
    /// automatically.
    @discardableResult
    public func launch() throws -> WritableByteStream {
        precondition(arguments.count > 0 && !arguments[0].isEmpty, "Need at least one argument to launch the process.")

        self.launchedLock.withLock {
            precondition(!self._launched, "It is not allowed to launch the same process object again.")
            self._launched = true
        }

        // Print the arguments if we are verbose.
        if let loggingHandler = self.loggingHandler {
            loggingHandler(arguments.joined(separator: " "))
        }

        // Look for executable.
        let executable = arguments[0]
        let executablePath = URL(fileURLWithPath: executable)
        //        guard let executablePath = Process.findExecutable(executable, workingDirectory: workingDirectory) else {
        //            throw Process.Error.missingExecutableProgram(program: executable)
        //        }

#if os(Windows)
        let process = Foundation.Process()
        _process = process
        process.arguments = Array(arguments.dropFirst()) // Avoid including the executable URL twice.
        process.executableURL = executablePath.asURL
        process.environment = environment

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        let group = DispatchGroup()

        var stdout: [UInt8] = []
        let stdoutLock = Lock()

        var stderr: [UInt8] = []
        let stderrLock = Lock()

        if outputRedirection.redirectsOutput {
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            group.enter()
            stdoutPipe.fileHandleForReading.readabilityHandler = { (fh : FileHandle) -> Void in
                let data = fh.availableData
                if (data.count == 0) {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                } else {
                    let contents = data.withUnsafeBytes { Array<UInt8>($0) }
                    self.outputRedirection.outputClosures?.stdoutClosure(contents)
                    stdoutLock.withLock {
                        stdout += contents
                    }
                }
            }

            group.enter()
            stderrPipe.fileHandleForReading.readabilityHandler = { (fh : FileHandle) -> Void in
                let data = fh.availableData
                if (data.count == 0) {
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    group.leave()
                } else {
                    let contents = data.withUnsafeBytes { Array<UInt8>($0) }
                    self.outputRedirection.outputClosures?.stderrClosure(contents)
                    stderrLock.withLock {
                        stderr += contents
                    }
                }
            }

            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
        }

        // first set state then start reading threads
        let sync = DispatchGroup()
        sync.enter()
        self.stateLock.withLock {
            self.state = .readingOutput(sync: sync)
        }

        group.notify(queue: self.completionQueue) {
            self.stateLock.withLock {
                self.state = .outputReady(stdout: .success(stdout), stderr: .success(stderr))
            }
            sync.leave()
        }

        try process.run()
        return stdinPipe.fileHandleForWriting
#elseif (!canImport(Darwin) || os(macOS)) || targetEnvironment(macCatalyst)
        // Initialize the spawn attributes.
#if canImport(Darwin) || os(Android) || os(OpenBSD)
        var attributes: posix_spawnattr_t? = nil
#else
        var attributes = posix_spawnattr_t()
#endif
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }

        // Unmask all signals.
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        // Reset all signals to default behavior.
#if canImport(Darwin)
        var mostSignals = sigset_t()
        sigfillset(&mostSignals)
        sigdelset(&mostSignals, SIGKILL)
        sigdelset(&mostSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &mostSignals)
#else
        // On Linux, this can only be used to reset signals that are legal to
        // modify, so we have to take care about the set we use.
        var mostSignals = sigset_t()
        sigemptyset(&mostSignals)
        for i in 1 ..< SIGSYS {
            if i == SIGKILL || i == SIGSTOP {
                continue
            }
            sigaddset(&mostSignals, i)
        }
        posix_spawnattr_setsigdefault(&attributes, &mostSignals)
#endif

        // Set the attribute flags.
        var flags = POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
        if startNewProcessGroup {
            // Establish a separate process group.
            flags |= POSIX_SPAWN_SETPGROUP
            posix_spawnattr_setpgroup(&attributes, 0)
        }

        posix_spawnattr_setflags(&attributes, Int16(flags))

        // Setup the file actions.
#if canImport(Darwin) || os(Android) || os(OpenBSD)
        var fileActions: posix_spawn_file_actions_t? = nil
#else
        var fileActions = posix_spawn_file_actions_t()
#endif
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        if let workingDirectory = workingDirectory?.path {
#if canImport(Darwin) && !targetEnvironment(macCatalyst)
            // The only way to set a workingDirectory is using an availability-gated initializer, so we don't need
            // to handle the case where the posix_spawn_file_actions_addchdir_np method is unavailable. This check only
            // exists here to make the compiler happy.
            if #available(macOS 10.15, *) {
                posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
            }
#elseif os(Linux)
            guard SPM_posix_spawn_file_actions_addchdir_np_supported() else {
                throw Process.Error.workingDirectoryNotSupported
            }

            SPM_posix_spawn_file_actions_addchdir_np(&fileActions, workingDirectory)
#else
            throw Process.Error.workingDirectoryNotSupported
#endif
        }

        var stdinPipe: [Int32] = [-1, -1]
        try open(pipe: &stdinPipe)

        let stdinStream = try LocalFileOutputByteStream(filePointer: fdopen(stdinPipe[1], "wb"), closeOnDeinit: true)

        // Dupe the read portion of the remote to 0.
        posix_spawn_file_actions_adddup2(&fileActions, stdinPipe[0], 0)

        // Close the other side's pipe since it was dupped to 0.
        posix_spawn_file_actions_addclose(&fileActions, stdinPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stdinPipe[1])

        var outputPipe: [Int32] = [-1, -1]
        var stderrPipe: [Int32] = [-1, -1]
        if outputRedirection.redirectsOutput {
            // Open the pipe.
            try open(pipe: &outputPipe)

            // Open the write end of the pipe.
            posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], 1)

            // Close the other ends of the pipe since they were dupped to 1.
            posix_spawn_file_actions_addclose(&fileActions, outputPipe[0])
            posix_spawn_file_actions_addclose(&fileActions, outputPipe[1])

            if outputRedirection.redirectStderr {
                // If merged was requested, send stderr to stdout.
                posix_spawn_file_actions_adddup2(&fileActions, 1, 2)
            } else {
                // If no redirect was requested, open the pipe for stderr.
                try open(pipe: &stderrPipe)
                posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], 2)

                // Close the other ends of the pipe since they were dupped to 2.
                posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0])
                posix_spawn_file_actions_addclose(&fileActions, stderrPipe[1])
            }
        } else {
            posix_spawn_file_actions_adddup2(&fileActions, 1, 1)
            posix_spawn_file_actions_adddup2(&fileActions, 2, 2)
        }

        var resolvedArgs = arguments
        if workingDirectory != nil {
            resolvedArgs[0] = executablePath.path
        }
        let argv = CStringArray(resolvedArgs)
        let env = CStringArray(environment.map({ "\($0.0)=\($0.1)" }))
        let rv = posix_spawnp(&processID, argv.cArray[0]!, &fileActions, &attributes, argv.cArray, env.cArray)

        guard rv == 0 else {
            throw SystemError.posix_spawn(rv, arguments)
        }

        // Close the local read end of the input pipe.
        try close(fd: stdinPipe[0])

        let group = DispatchGroup()
        if !outputRedirection.redirectsOutput {
            // no stdout or stderr in this case
            self.stateLock.withLock {
                self.state = .outputReady(stdout: .success([]), stderr: .success([]))
            }
        } else {
            var pending: Result<[UInt8], Swift.Error>?
            let pendingLock = NSLock()

            let outputClosures = outputRedirection.outputClosures

            // Close the local write end of the output pipe.
            try close(fd: outputPipe[1])

            // Create a thread and start reading the output on it.
            group.enter()
            let stdoutThread = Thread { [weak self] in
                if let readResult = self?.readOutput(onFD: outputPipe[0], outputClosure: outputClosures?.stdoutClosure) {
                    pendingLock.withLock {
                        if let stderrResult = pending {
                            self?.stateLock.withLock {
                                self?.state = .outputReady(stdout: readResult, stderr: stderrResult)
                            }
                        } else  {
                            pending = readResult
                        }
                    }
                    group.leave()
                } else if let stderrResult = (pendingLock.withLock { pending }) {
                    // TODO: this is more of an error
                    self?.stateLock.withLock {
                        self?.state = .outputReady(stdout: .success([]), stderr: stderrResult)
                    }
                    group.leave()
                }
            }

            // Only schedule a thread for stderr if no redirect was requested.
            var stderrThread: Thread? = nil
            if !outputRedirection.redirectStderr {
                // Close the local write end of the stderr pipe.
                try close(fd: stderrPipe[1])

                // Create a thread and start reading the stderr output on it.
                group.enter()
                stderrThread = Thread { [weak self] in
                    if let readResult = self?.readOutput(onFD: stderrPipe[0], outputClosure: outputClosures?.stderrClosure) {
                        pendingLock.withLock {
                            if let stdoutResult = pending {
                                self?.stateLock.withLock {
                                    self?.state = .outputReady(stdout: stdoutResult, stderr: readResult)
                                }
                            } else {
                                pending = readResult
                            }
                        }
                        group.leave()
                    } else if let stdoutResult = (pendingLock.withLock { pending }) {
                        // TODO: this is more of an error
                        self?.stateLock.withLock {
                            self?.state = .outputReady(stdout: stdoutResult, stderr: .success([]))
                        }
                        group.leave()
                    }
                }
            } else {
                pendingLock.withLock {
                    pending = .success([])  // no stderr in this case
                }
            }

            // first set state then start reading threads
            self.stateLock.withLock {
                self.state = .readingOutput(sync: group)
            }

            stdoutThread.start()
            stderrThread?.start()
        }

        return stdinStream
#else
        preconditionFailure("Process spawning is not available")
#endif // POSIX implementation
    }

    /// Executes the process I/O state machine, returning the result when finished.
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    public func waitUntilExit() async throws -> ProcessResult {
#if compiler(>=5.6)
        return try await withCheckedThrowingContinuation { continuation in
            waitUntilExit(continuation.resume(with:))
        }
#else
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            return try await withCheckedThrowingContinuation { continuation in
                waitUntilExit(continuation.resume(with:))
            }
        } else {
            preconditionFailure("Unsupported with Swift 5.5 on this OS version")
        }
#endif
    }

    /// Blocks the calling process until the subprocess finishes execution.
    //    #if compiler(>=5.8)
    //    @available(*, noasync)
    //    #endif
    @discardableResult
    public func waitUntilExit() throws -> ProcessResult {
        let group = DispatchGroup()
        group.enter()
        var processResult : Result<ProcessResult, Swift.Error>?
        self.waitUntilExit() { result in
            processResult = result
            group.leave()
        }
        group.wait()
        return try processResult.unsafelyUnwrapped.get()
    }

    /// Executes the process I/O state machine, calling completion block when finished.
    private func waitUntilExit(_ completion: @escaping (Result<ProcessResult, Swift.Error>) -> Void) {
        self.stateLock.lock()
        switch self.state {
        case .idle:
            defer { self.stateLock.unlock() }
            preconditionFailure("The process is not yet launched.")
        case .complete(let result):
            self.stateLock.unlock()
            completion(.success(result))
        case .failed(let error):
            self.stateLock.unlock()
            completion(.failure(error))
        case .readingOutput(let sync):
            self.stateLock.unlock()
            sync.notify(queue: self.completionQueue) {
                self.waitUntilExit(completion)
            }
        case .outputReady(let stdoutResult, let stderrResult):
            defer { self.stateLock.unlock() }
            // Wait until process finishes execution.
#if os(Windows)
            precondition(_process != nil, "The process is not yet launched.")
            let p = _process!
            p.waitUntilExit()
            let exitStatusCode = p.terminationStatus
            let normalExit = p.terminationReason == .exit
#else
            var exitStatusCode: Int32 = 0
            var result = waitpid(processID, &exitStatusCode, 0)
            while result == -1 && errno == EINTR {
                result = waitpid(processID, &exitStatusCode, 0)
            }
            if result == -1 {
                self.state = .failed(SystemError.waitpid(errno))
            }
            let normalExit = !WIFSIGNALED(result)
#endif

            // Construct the result.
            let executionResult = ProcessResult(
                arguments: arguments,
                environment: environment,
                exitStatusCode: exitStatusCode,
                normal: normalExit,
                output: stdoutResult,
                stderrOutput: stderrResult
            )
            self.state = .complete(executionResult)
            self.completionQueue.async {
                self.waitUntilExit(completion)
            }
        }
    }

#if !os(Windows)
    /// Reads the given fd and returns its result.
    ///
    /// Closes the fd before returning.
    private func readOutput(onFD fd: Int32, outputClosure: OutputClosure?) -> Result<[UInt8], Swift.Error> {
        // Read all of the data from the output pipe.
        let N = 4096
        var buf = [UInt8](repeating: 0, count: N + 1)

        var out = [UInt8]()
        var error: Swift.Error? = nil
    loop: while true {
        let n = read(fd, &buf, N)
        switch n {
        case  -1:
            if errno == EINTR {
                continue
            } else {
                error = SystemError.read(errno)
                break loop
            }
        case 0:
            // Close the read end of the output pipe.
            // We should avoid closing the read end of the pipe in case
            // -1 because the child process may still have content to be
            // flushed into the write end of the pipe. If the read end of the
            // pipe is closed, then a write will cause a SIGPIPE signal to
            // be generated for the calling process.  If the calling process is
            // ignoring this signal, then write fails with the error EPIPE.
            close(fd)
            break loop
        default:
            let data = buf[0..<n]
            if let outputClosure = outputClosure {
                outputClosure(Array(data))
            } else {
                out += data
            }
        }
    }
        // Construct the output result.
        return error.map(Result.failure) ?? .success(out)
    }
#endif

    /// Send a signal to the process.
    ///
    /// Note: This will signal all processes in the process group.
    public func signal(_ signal: Int32) {
#if os(Windows)
        if signal == SIGINT {
            _process?.interrupt()
        } else {
            _process?.terminate()
        }
#else
        assert(self.launched, "The process is not yet launched.")
        _ = Darwin.kill(startNewProcessGroup ? -processID : processID, signal)
#endif
    }
}

extension Process {
    /// Execute a subprocess and returns the result when it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    static public func popen(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> ProcessResult {
        let process = Process(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            loggingHandler: loggingHandler
        )
        try process.launch()
        return try await process.waitUntilExit()
    }

    /// Execute a subprocess and returns the result when it finishes execution
    ///
    /// - Parameters:
    ///   - args: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    static public func popen(
        args: String...,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> ProcessResult {
        try await popen(arguments: args, environment: environment, loggingHandler: loggingHandler)
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    static public func checkNonZeroExit(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> String {
        let result = try await popen(arguments: arguments, environment: environment, loggingHandler: loggingHandler)
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
        return try result.utf8Output()
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - args: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    @available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
    @discardableResult
    static public func checkNonZeroExit(
        args: String...,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) async throws -> String {
        try await checkNonZeroExit(arguments: args, environment: environment, loggingHandler: loggingHandler)
    }
}

extension Process {
    /// Execute a subprocess and calls completion block when it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    ///   - queue: Queue to use for callbacks
    ///   - completion: A completion handler to return the process result
    //    #if compiler(>=5.8)
    //    @available(*, noasync)
    //    #endif
    static public func popen(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none,
        queue: DispatchQueue? = nil,
        completion: @escaping (Result<ProcessResult, Swift.Error>) -> Void
    ) {
        let completionQueue = queue ?? Self.sharedCompletionQueue

        do {
            let process = Process(
                arguments: arguments,
                environment: environment,
                outputRedirection: .collect,
                loggingHandler: loggingHandler
            )
            process.completionQueue = completionQueue
            try process.launch()
            process.waitUntilExit(completion)
        } catch {
            completionQueue.async {
                completion(.failure(error))
            }
        }
    }

    /// Execute a subprocess and block until it finishes execution
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process result.
    //    #if compiler(>=5.8)
    //    @available(*, noasync)
    //    #endif
    @discardableResult
    static public func popen(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) throws -> ProcessResult {
        let process = Process(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            loggingHandler: loggingHandler
        )
        try process.launch()
        return try process.waitUntilExit()
    }

    /// Execute a subprocess and block until it finishes execution
    ///
    /// - Parameters:
    ///   - args: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process result.
    //    #if compiler(>=5.8)
    //    @available(*, noasync)
    //    #endif
    @discardableResult
    static public func popen(
        args: String...,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) throws -> ProcessResult {
        return try Process.popen(arguments: args, environment: environment, loggingHandler: loggingHandler)
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    //    #if compiler(>=5.8)
    //    @available(*, noasync)
    //    #endif
    @discardableResult
    static public func checkNonZeroExit(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) throws -> String {
        let process = Process(
            arguments: arguments,
            environment: environment,
            outputRedirection: .collect,
            loggingHandler: loggingHandler
        )
        try process.launch()
        let result = try process.waitUntilExit()
        // Throw if there was a non zero termination.
        guard result.exitStatus == .terminated(code: 0) else {
            throw ProcessResult.Error.nonZeroExit(result)
        }
        return try result.utf8Output()
    }

    /// Execute a subprocess and get its (UTF-8) output if it has a non zero exit.
    ///
    /// - Parameters:
    ///   - arguments: The arguments for the subprocess.
    ///   - environment: The environment to pass to subprocess. By default the current process environment
    ///     will be inherited.
    ///   - loggingHandler: Handler for logging messages
    /// - Returns: The process output (stdout + stderr).
    //    #if compiler(>=5.8)
    //    @available(*, noasync)
    //    #endif
    @discardableResult
    static public func checkNonZeroExit(
        args: String...,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        loggingHandler: LoggingHandler? = .none
    ) throws -> String {
        return try checkNonZeroExit(arguments: args, environment: environment, loggingHandler: loggingHandler)
    }
}

extension Process: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    public static func == (lhs: Process, rhs: Process) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }
}


#if swift(<5.6)
extension Process: UnsafeSendable {}
#else
extension Process: @unchecked Sendable {}
#endif


public enum SystemError: Error {
    case chdir(Int32, String)
    case close(Int32)
    case exec(Int32, path: String, args: [String])
    case pipe(Int32)
    case posix_spawn(Int32, [String])
    case read(Int32)
    case setenv(Int32, String)
    case stat(Int32, String)
    case symlink(Int32, String, dest: String)
    case unsetenv(Int32, String)
    case waitpid(Int32)
}

extension SystemError: CustomStringConvertible {
    public var description: String {
        func strerror(_ errno: Int32) -> String {
#if os(Windows)
            let cap = 128
            var buf = [Int8](repeating: 0, count: cap)
            let _ = Darwin.strerror_s(&buf, 128, errno)
            return "\(String(cString: buf)) (\(errno))"
#else
            var cap = 64
            while cap <= 16 * 1024 {
                var buf = [Int8](repeating: 0, count: cap)
                let err = Darwin.strerror_r(errno, &buf, buf.count)
                if err == EINVAL {
                    return "Unknown error \(errno)"
                }
                if err == ERANGE {
                    cap *= 2
                    continue
                }
                if err != 0 {
                    fatalError("strerror_r error: \(err)")
                }
                return "\(String(cString: buf)) (\(errno))"
            }
            fatalError("strerror_r error: \(ERANGE)")
#endif
        }

        switch self {
        case .chdir(let errno, let path):
            return "chdir error: \(strerror(errno)): \(path)"
        case .close(let errno):
            return "close error: \(strerror(errno))"
        case .exec(let errno, let path, let args):
            let joinedArgs = args.joined(separator: " ")
            return "exec error: \(strerror(errno)): \(path) \(joinedArgs)"
        case .pipe(let errno):
            return "pipe error: \(strerror(errno))"
        case .posix_spawn(let errno, let args):
            return "posix_spawn error: \(strerror(errno)), `\(args)`"
        case .read(let errno):
            return "read error: \(strerror(errno))"
        case .setenv(let errno, let key):
            return "setenv error: \(strerror(errno)): \(key)"
        case .stat(let errno, _):
            return "stat error: \(strerror(errno))"
        case .symlink(let errno, let path, let dest):
            return "symlink error: \(strerror(errno)): \(path) -> \(dest)"
        case .unsetenv(let errno, let key):
            return "unsetenv error: \(strerror(errno)): \(key)"
        case .waitpid(let errno):
            return "waitpid error: \(strerror(errno))"
        }
    }
}

extension SystemError: CustomNSError {
    public var errorUserInfo: [String : Any] {
        return [NSLocalizedDescriptionKey: self.description]
    }
}


/// Process result data which is available after process termination.
public struct ProcessResult: CustomStringConvertible, Sendable {

    public enum Error: Swift.Error, Sendable {
        /// The output is not a valid UTF8 sequence.
        case illegalUTF8Sequence

        /// The process had a non zero exit.
        case nonZeroExit(ProcessResult)
    }

    public enum ExitStatus: Equatable, Sendable {
        /// The process was terminated normally with a exit code.
        case terminated(code: Int32)
#if os(Windows)
        /// The process was terminated abnormally.
        case abnormal(exception: UInt32)
#else
        /// The process was terminated due to a signal.
        case signalled(signal: Int32)
#endif
    }

    /// The arguments with which the process was launched.
    public let arguments: [String]

    /// The environment with which the process was launched.
    public let environment: [String: String]

    /// The exit status of the process.
    public let exitStatus: ExitStatus

    /// The output bytes of the process. Available only if the process was
    /// asked to redirect its output and no stdout output closure was set.
    public let output: Result<[UInt8], Swift.Error>

    /// The output bytes of the process. Available only if the process was
    /// asked to redirect its output and no stderr output closure was set.
    public let stderrOutput: Result<[UInt8], Swift.Error>

    /// Create an instance using a POSIX process exit status code and output result.
    ///
    /// See `waitpid(2)` for information on the exit status code.
    public init(
        arguments: [String],
        environment: [String: String],
        exitStatusCode: Int32,
        normal: Bool,
        output: Result<[UInt8], Swift.Error>,
        stderrOutput: Result<[UInt8], Swift.Error>
    ) {
        let exitStatus: ExitStatus
#if os(Windows)
        if normal {
            exitStatus = .terminated(code: exitStatusCode)
        } else {
            exitStatus = .abnormal(exception: UInt32(exitStatusCode))
        }
#else
        if WIFSIGNALED(exitStatusCode) {
            exitStatus = .signalled(signal: WTERMSIG(exitStatusCode))
        } else {
            precondition(WIFEXITED(exitStatusCode), "unexpected exit status \(exitStatusCode)")
            exitStatus = .terminated(code: WEXITSTATUS(exitStatusCode))
        }
#endif
        self.init(arguments: arguments, environment: environment, exitStatus: exitStatus, output: output,
                  stderrOutput: stderrOutput)
    }

    /// Create an instance using an exit status and output result.
    public init(
        arguments: [String],
        environment: [String: String],
        exitStatus: ExitStatus,
        output: Result<[UInt8], Swift.Error>,
        stderrOutput: Result<[UInt8], Swift.Error>
    ) {
        self.arguments = arguments
        self.environment = environment
        self.output = output
        self.stderrOutput = stderrOutput
        self.exitStatus = exitStatus
    }

    /// Converts stdout output bytes to string, assuming they're UTF8.
    public func utf8Output() throws -> String {
        return String(decoding: try output.get(), as: Unicode.UTF8.self)
    }

    /// Converts stderr output bytes to string, assuming they're UTF8.
    public func utf8stderrOutput() throws -> String {
        return String(decoding: try stderrOutput.get(), as: Unicode.UTF8.self)
    }

    public var description: String {
        return """
            <ProcessResult: exit: \(exitStatus), output:
             \((try? utf8Output().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "")
            >
            """
    }
}

// MARK: - Private helpers
#if !os(Windows)
#if canImport(Darwin)
private typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t?
#else
private typealias swiftpm_posix_spawn_file_actions_t = posix_spawn_file_actions_t
#endif

private func WIFEXITED(_ status: Int32) -> Bool {
    return _WSTATUS(status) == 0
}

private func _WSTATUS(_ status: Int32) -> Int32 {
    return status & 0x7f
}

private func WIFSIGNALED(_ status: Int32) -> Bool {
    return (_WSTATUS(status) != 0) && (_WSTATUS(status) != 0x7f)
}

private func WEXITSTATUS(_ status: Int32) -> Int32 {
    return (status >> 8) & 0xff
}

private func WTERMSIG(_ status: Int32) -> Int32 {
    return status & 0x7f
}

#if canImport(Darwin)

/// Open the given pipe.
private func open(pipe: inout [Int32]) throws {
    let rv = Darwin.pipe(&pipe)
    guard rv == 0 else {
        throw SystemError.pipe(rv)
    }
}

/// Close the given fd.
private func close(fd: Int32) throws {
    func innerClose(_ fd: inout Int32) throws {
        let rv = Darwin.close(fd)
        guard rv == 0 else {
            throw SystemError.close(rv)
        }
    }
    var innerFd = fd
    try innerClose(&innerFd)
}

#endif

extension Process.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingExecutableProgram(let program):
            return "could not find executable for '\(program)'"
        case .workingDirectoryNotSupported:
            return "workingDirectory is not supported in this platform"
        }
    }
}

extension Process.Error: CustomNSError {
    public var errorUserInfo: [String : Any] {
        return [NSLocalizedDescriptionKey: self.description]
    }
}

#endif

extension ProcessResult.Error: CustomStringConvertible {
    public var description: String {
        switch self {
        case .illegalUTF8Sequence:
            return "illegal UTF8 sequence output"
        case .nonZeroExit(let result):
            let stream = BufferedOutputByteStream()
            switch result.exitStatus {
            case .terminated(let code):
                stream <<< "terminated(\(code)): "
#if os(Windows)
            case .abnormal(let exception):
                stream <<< "abnormal(\(exception)): "
#else
            case .signalled(let signal):
                stream <<< "signalled(\(signal)): "
#endif
            }

            // Strip sandbox information from arguments to keep things pretty.
            var args = result.arguments
            // This seems a little fragile.
            if args.first == "sandbox-exec", args.count > 3 {
                args = args.suffix(from: 3).map({$0})
            }
            stream <<< args.joined(separator: " ")

            // Include the output, if present.
            if let output = try? result.utf8Output() + result.utf8stderrOutput() {
                // We indent the output to keep it visually separated from everything else.
                let indentation = "    "
                stream <<< " output:\n" <<< indentation <<< output.replacingOccurrences(of: "\n", with: "\n" + indentation)
                if !output.hasSuffix("\n") {
                    stream <<< "\n"
                }
            }

            return stream.bytes.description
        }
    }
}

#if os(Windows)
extension FileHandle: WritableByteStream {
    public var position: Int {
        return Int(offsetInFile)
    }

    public func write(_ byte: UInt8) {
        write(Data([byte]))
    }

    public func write<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        write(Data(bytes))
    }

    public func flush() {
        synchronizeFile()
    }
}
#endif


extension Process {
    @available(*, deprecated)
    fileprivate static func logToStdout(_ message: String) {
        stdoutStream <<< message <<< "\n"
        stdoutStream.flush()
    }
}

/// `CStringArray` represents a C null-terminated array of pointers to C strings.
///
/// The lifetime of the C strings will correspond to the lifetime of the `CStringArray`
/// instance so be careful about copying the buffer as it may contain dangling pointers.
public final class CStringArray {
    /// The null-terminated array of C string pointers.
    public let cArray: [UnsafeMutablePointer<Int8>?]

    /// Creates an instance from an array of strings.
    public init(_ array: [String]) {
#if os(Windows)
        cArray = array.map({ $0.withCString({ _strdup($0) }) }) + [nil]
#else
        cArray = array.map({ $0.withCString({ strdup($0) }) }) + [nil]
#endif
    }

    deinit {
        for case let element? in cArray {
            free(element)
        }
    }
}


/// Closable entity is one that manages underlying resources and needs to be closed for cleanup
/// The intent of this method is for the sole owner of the refernece/handle of the resource to close it completely, comapred to releasing a shared resource.
public protocol Closable {
    func close() throws
}


/// Convert an integer in 0..<16 to its hexadecimal ASCII character.
private func hexdigit(_ value: UInt8) -> UInt8 {
    return value < 10 ? (0x30 + value) : (0x41 + value - 10)
}

/// Describes a type which can be written to a byte stream.
public protocol ByteStreamable {
    func write(to stream: WritableByteStream)
}

/// An output byte stream.
///
/// This protocol is designed to be able to support efficient streaming to
/// different output destinations, e.g., a file or an in memory buffer. This is
/// loosely modeled on LLVM's llvm::raw_ostream class.
///
/// The stream is generally used in conjunction with the custom streaming
/// operator '<<<'. For example:
///
///   let stream = BufferedOutputByteStream()
///   stream <<< "Hello, world!"
///
/// would write the UTF8 encoding of "Hello, world!" to the stream.
///
/// The stream accepts a number of custom formatting operators which are defined
/// in the `Format` struct (used for namespacing purposes). For example:
///
///   let items = ["hello", "world"]
///   stream <<< Format.asSeparatedList(items, separator: " ")
///
/// would write each item in the list to the stream, separating them with a
/// space.
public protocol WritableByteStream: AnyObject, TextOutputStream, Closable {
    /// The current offset within the output stream.
    var position: Int { get }

    /// Write an individual byte to the buffer.
    func write(_ byte: UInt8)

    /// Write a collection of bytes to the buffer.
    func write<C: Collection>(_ bytes: C) where C.Element == UInt8

    /// Flush the stream's buffer.
    func flush()
}

// Default noop implementation of close to avoid source-breaking downstream dependents with the addition of the close
// API.
public extension WritableByteStream {
    func close() throws { }
}

// Public alias to the old name to not introduce API compatibility.
public typealias OutputByteStream = WritableByteStream

#if os(Android)
public typealias FILEPointer = OpaquePointer
#else
public typealias FILEPointer = UnsafeMutablePointer<FILE>
#endif

extension WritableByteStream {
    /// Write a sequence of bytes to the buffer.
    public func write<S: Sequence>(sequence: S) where S.Iterator.Element == UInt8 {
        // Iterate the sequence and append byte by byte since sequence's append
        // is not performant anyway.
        for byte in sequence {
            write(byte)
        }
    }

    /// Write a string to the buffer (as UTF8).
    public func write(_ string: String) {
        // FIXME(performance): Use `string.utf8._copyContents(initializing:)`.
        write(string.utf8)
    }

    /// Write a string (as UTF8) to the buffer, with escaping appropriate for
    /// embedding within a JSON document.
    ///
    /// - Note: This writes the literal data applying JSON string escaping, but
    ///         does not write any other characters (like the quotes that would surround
    ///         a JSON string).
    public func writeJSONEscaped(_ string: String) {
        // See RFC7159 for reference: https://tools.ietf.org/html/rfc7159
        for character in string.utf8 {
            // Handle string escapes; we use constants here to directly match the RFC.
            switch character {
                // Literal characters.
            case 0x20...0x21, 0x23...0x5B, 0x5D...0xFF:
                write(character)

                // Single-character escaped characters.
            case 0x22: // '"'
                write(0x5C) // '\'
                write(0x22) // '"'
            case 0x5C: // '\\'
                write(0x5C) // '\'
                write(0x5C) // '\'
            case 0x08: // '\b'
                write(0x5C) // '\'
                write(0x62) // 'b'
            case 0x0C: // '\f'
                write(0x5C) // '\'
                write(0x66) // 'b'
            case 0x0A: // '\n'
                write(0x5C) // '\'
                write(0x6E) // 'n'
            case 0x0D: // '\r'
                write(0x5C) // '\'
                write(0x72) // 'r'
            case 0x09: // '\t'
                write(0x5C) // '\'
                write(0x74) // 't'
                // Multi-character escaped characters.
            default:
                write(0x5C) // '\'
                write(0x75) // 'u'
                write(hexdigit(0))
                write(hexdigit(0))
                write(hexdigit(character >> 4))
                write(hexdigit(character & 0xF))
            }
        }
    }
}

/// The `WritableByteStream` base class.
///
/// This class provides a base and efficient implementation of the `WritableByteStream`
/// protocol. It can not be used as is-as subclasses as several functions need to be
/// implemented in subclasses.
public class _WritableByteStreamBase: WritableByteStream {
    /// If buffering is enabled
    @usableFromInline let _buffered : Bool

    /// The data buffer.
    /// - Note: Minimum Buffer size should be one.
    @usableFromInline var _buffer: [UInt8]

    /// Default buffer size of the data buffer.
    private static let bufferSize = 1024

    /// Queue to protect mutating operation.
    fileprivate let queue = DispatchQueue(label: "org.swift.swiftpm.basic.stream")

    init(buffered: Bool) {
        self._buffered = buffered
        self._buffer = []

        // When not buffered we still reserve 1 byte, as it is used by the
        // by the single byte write() variant.
        self._buffer.reserveCapacity(buffered ? _WritableByteStreamBase.bufferSize : 1)
    }

    // MARK: Data Access API
    /// The current offset within the output stream.
    public var position: Int {
        return _buffer.count
    }

    /// Currently available buffer size.
    @usableFromInline var _availableBufferSize: Int {
        return _buffer.capacity - _buffer.count
    }

    /// Clears the buffer maintaining current capacity.
    @usableFromInline func _clearBuffer() {
        _buffer.removeAll(keepingCapacity: true)
    }

    // MARK: Data Output API
    public final func flush() {
        writeImpl(ArraySlice(_buffer))
        _clearBuffer()
        flushImpl()
    }

    @usableFromInline func flushImpl() {
        // Do nothing.
    }

    public final func close() throws {
        try closeImpl()
    }

    @usableFromInline func closeImpl() throws {
        fatalError("Subclasses must implement this")
    }

    @usableFromInline func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        fatalError("Subclasses must implement this")
    }

    @usableFromInline func writeImpl(_ bytes: ArraySlice<UInt8>) {
        fatalError("Subclasses must implement this")
    }

    /// Write an individual byte to the buffer.
    public final func write(_ byte: UInt8) {
        guard _buffered else {
            _buffer.append(byte)
            writeImpl(ArraySlice(_buffer))
            flushImpl()
            _clearBuffer()
            return
        }

        // If buffer is full, write and clear it.
        if _availableBufferSize == 0 {
            writeImpl(ArraySlice(_buffer))
            _clearBuffer()
        }

        // This will need to change change if we ever have unbuffered stream.
        precondition(_availableBufferSize > 0)
        _buffer.append(byte)
    }

    /// Write a collection of bytes to the buffer.
    @inlinable public final func write<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        guard _buffered else {
            if let b = bytes as? ArraySlice<UInt8> {
                // Fast path for unbuffered ArraySlice
                writeImpl(b)
            } else if let b = bytes as? Array<UInt8> {
                // Fast path for unbuffered Array
                writeImpl(ArraySlice(b))
            } else {
                // generic collection unfortunately must be temporarily buffered
                writeImpl(bytes)
            }
            flushImpl()
            return
        }

        // This is based on LLVM's raw_ostream.
        let availableBufferSize = self._availableBufferSize
        let byteCount = Int(bytes.count)

        // If we have to insert more than the available space in buffer.
        if byteCount > availableBufferSize {
            // If buffer is empty, start writing and keep the last chunk in buffer.
            if _buffer.isEmpty {
                let bytesToWrite = byteCount - (byteCount % availableBufferSize)
                let writeUptoIndex = bytes.index(bytes.startIndex, offsetBy: numericCast(bytesToWrite))
                writeImpl(bytes.prefix(upTo: writeUptoIndex))

                // If remaining bytes is more than buffer size write everything.
                let bytesRemaining = byteCount - bytesToWrite
                if bytesRemaining > availableBufferSize {
                    writeImpl(bytes.suffix(from: writeUptoIndex))
                    return
                }
                // Otherwise keep remaining in buffer.
                _buffer += bytes.suffix(from: writeUptoIndex)
                return
            }

            let writeUptoIndex = bytes.index(bytes.startIndex, offsetBy: numericCast(availableBufferSize))
            // Append whatever we can accommodate.
            _buffer += bytes.prefix(upTo: writeUptoIndex)

            writeImpl(ArraySlice(_buffer))
            _clearBuffer()

            // FIXME: We should start again with remaining chunk but this doesn't work. Write everything for now.
            //write(collection: bytes.suffix(from: writeUptoIndex))
            writeImpl(bytes.suffix(from: writeUptoIndex))
            return
        }
        _buffer += bytes
    }
}

/// The thread-safe wrapper around output byte streams.
///
/// This class wraps any `WritableByteStream` conforming type to provide a type-safe
/// access to its operations. If the provided stream inherits from `_WritableByteStreamBase`,
/// it will also ensure it is type-safe will all other `ThreadSafeOutputByteStream` instances
/// around the same stream.
public final class ThreadSafeOutputByteStream: WritableByteStream {
    private static let defaultQueue = DispatchQueue(label: "org.swift.swiftpm.basic.thread-safe-output-byte-stream")
    public let stream: WritableByteStream
    private let queue: DispatchQueue

    public var position: Int {
        return queue.sync {
            stream.position
        }
    }

    public init(_ stream: WritableByteStream) {
        self.stream = stream
        self.queue = (stream as? _WritableByteStreamBase)?.queue ?? ThreadSafeOutputByteStream.defaultQueue
    }

    public func write(_ byte: UInt8) {
        queue.sync {
            stream.write(byte)
        }
    }

    public func write<C: Collection>(_ bytes: C) where C.Element == UInt8 {
        queue.sync {
            stream.write(bytes)
        }
    }

    public func flush() {
        queue.sync {
            stream.flush()
        }
    }

    public func write<S: Sequence>(sequence: S) where S.Iterator.Element == UInt8 {
        queue.sync {
            stream.write(sequence: sequence)
        }
    }

    public func writeJSONEscaped(_ string: String) {
        queue.sync {
            stream.writeJSONEscaped(string)
        }
    }

    public func close() throws {
        try queue.sync {
            try stream.close()
        }
    }
}


#if swift(<5.6)
extension ThreadSafeOutputByteStream: UnsafeSendable {}
#else
extension ThreadSafeOutputByteStream: @unchecked Sendable {}
#endif

/// Define an output stream operator. We need it to be left associative, so we
/// use `<<<`.
infix operator <<< : StreamingPrecedence
precedencegroup StreamingPrecedence {
    associativity: left
}

// MARK: Output Operator Implementations
// FIXME: This override shouldn't be necesary but removing it causes a 30% performance regression. This problem is
// tracked by the following bug: https://bugs.swift.org/browse/SR-8535
@discardableResult
public func <<< (stream: WritableByteStream, value: ArraySlice<UInt8>) -> WritableByteStream {
    value.write(to: stream)
    return stream
}

@discardableResult
public func <<< (stream: WritableByteStream, value: ByteStreamable) -> WritableByteStream {
    value.write(to: stream)
    return stream
}

@discardableResult
public func <<< (stream: WritableByteStream, value: CustomStringConvertible) -> WritableByteStream {
    value.description.write(to: stream)
    return stream
}

@discardableResult
public func <<< (stream: WritableByteStream, value: ByteStreamable & CustomStringConvertible) -> WritableByteStream {
    value.write(to: stream)
    return stream
}

extension UInt8: ByteStreamable {
    public func write(to stream: WritableByteStream) {
        stream.write(self)
    }
}

extension Character: ByteStreamable {
    public func write(to stream: WritableByteStream) {
        stream.write(String(self))
    }
}

extension String: ByteStreamable {
    public func write(to stream: WritableByteStream) {
        stream.write(self.utf8)
    }
}

extension Substring: ByteStreamable {
    public func write(to stream: WritableByteStream) {
        stream.write(self.utf8)
    }
}

extension StaticString: ByteStreamable {
    public func write(to stream: WritableByteStream) {
        withUTF8Buffer { stream.write($0) }
    }
}

extension Array: ByteStreamable where Element == UInt8 {
    public func write(to stream: WritableByteStream) {
        stream.write(self)
    }
}

extension ArraySlice: ByteStreamable where Element == UInt8 {
    public func write(to stream: WritableByteStream) {
        stream.write(self)
    }
}

extension ContiguousArray: ByteStreamable where Element == UInt8 {
    public func write(to stream: WritableByteStream) {
        stream.write(self)
    }
}


/// A `ByteString` represents a sequence of bytes.
///
/// This struct provides useful operations for working with buffers of
/// bytes. Conceptually it is just a contiguous array of bytes (UInt8), but it
/// contains methods and default behavior suitable for common operations done
/// using bytes strings.
///
/// This struct *is not* intended to be used for significant mutation of byte
/// strings, we wish to retain the flexibility to micro-optimize the memory
/// allocation of the storage (for example, by inlining the storage for small
/// strings or and by eliminating wasted space in growable arrays). For
/// construction of byte arrays, clients should use the `WritableByteStream` class
/// and then convert to a `ByteString` when complete.
public struct ByteString: ExpressibleByArrayLiteral, Hashable, Sendable {
    /// The buffer contents.
    @usableFromInline
    internal var _bytes: [UInt8]

    /// Create an empty byte string.
    @inlinable
    public init() {
        _bytes = []
    }

    /// Create a byte string from a byte array literal.
    @inlinable
    public init(arrayLiteral contents: UInt8...) {
        _bytes = contents
    }

    /// Create a byte string from an array of bytes.
    @inlinable
    public init(_ contents: [UInt8]) {
        _bytes = contents
    }

    /// Create a byte string from an array slice.
    @inlinable
    public init(_ contents: ArraySlice<UInt8>) {
        _bytes = Array(contents)
    }

    /// Create a byte string from an byte buffer.
    @inlinable
    public init<S: Sequence> (_ contents: S) where S.Iterator.Element == UInt8 {
        _bytes = [UInt8](contents)
    }

    /// Create a byte string from the UTF8 encoding of a string.
    @inlinable
    public init(encodingAsUTF8 string: String) {
        _bytes = [UInt8](string.utf8)
    }

    /// Access the byte string contents as an array.
    @inlinable
    public var contents: [UInt8] {
        return _bytes
    }

    /// Return the byte string size.
    @inlinable
    public var count: Int {
        return _bytes.count
    }

    /// Gives a non-escaping closure temporary access to an immutable `Data` instance wrapping the `ByteString` without
    /// copying any memory around.
    ///
    /// - Parameters:
    ///   - closure: The closure that will have access to a `Data` instance for the duration of its lifetime.
    @inlinable
    public func withData<T>(_ closure: (Data) throws -> T) rethrows -> T {
        return try _bytes.withUnsafeBytes { pointer -> T in
            let mutatingPointer = UnsafeMutableRawPointer(mutating: pointer.baseAddress!)
            let data = Data(bytesNoCopy: mutatingPointer, count: pointer.count, deallocator: .none)
            return try closure(data)
        }
    }

    /// Returns a `String` lowercase hexadecimal representation of the contents of the `ByteString`.
    @inlinable
    public var hexadecimalRepresentation: String {
        _bytes.reduce("") {
            var str = String($1, radix: 16)
            // The above method does not do zero padding.
            if str.count == 1 {
                str = "0" + str
            }
            return $0 + str
        }
    }
}

/// Conform to CustomDebugStringConvertible.
extension ByteString: CustomStringConvertible {
    /// Return the string decoded as a UTF8 sequence, or traps if not possible.
    public var description: String {
        return cString
    }

    /// Return the string decoded as a UTF8 sequence, if possible.
    @inlinable
    public var validDescription: String? {
        // FIXME: This is very inefficient, we need a way to pass a buffer. It
        // is also wrong if the string contains embedded '\0' characters.
        let tmp = _bytes + [UInt8(0)]
        return tmp.withUnsafeBufferPointer { ptr in
            return String(validatingUTF8: unsafeBitCast(ptr.baseAddress, to: UnsafePointer<CChar>.self))
        }
    }

    /// Return the string decoded as a UTF8 sequence, substituting replacement
    /// characters for ill-formed UTF8 sequences.
    @inlinable
    public var cString: String {
        return String(decoding: _bytes, as: Unicode.UTF8.self)
    }

    @available(*, deprecated, message: "use description or validDescription instead")
    public var asString: String? {
        return validDescription
    }
}

/// ByteStreamable conformance for a ByteString.
extension ByteString: ByteStreamable {
    @inlinable
    public func write(to stream: WritableByteStream) {
        stream.write(_bytes)
    }
}

/// StringLiteralConvertable conformance for a ByteString.
extension ByteString: ExpressibleByStringLiteral {
    public typealias UnicodeScalarLiteralType = StringLiteralType
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType

    public init(unicodeScalarLiteral value: UnicodeScalarLiteralType) {
        _bytes = [UInt8](value.utf8)
    }
    public init(extendedGraphemeClusterLiteral value: ExtendedGraphemeClusterLiteralType) {
        _bytes = [UInt8](value.utf8)
    }
    public init(stringLiteral value: StringLiteralType) {
        _bytes = [UInt8](value.utf8)
    }
}


/// Type of localized join operator.
public enum LocalizedJoinType: String {
    /// A conjunction join operator (ie: blue, white, and red)
    case conjunction = "and"

    /// A disjunction join operator (ie: blue, white, or red)
    case disjunction = "or"
}

//FIXME: Migrate to DiagnosticFragmentBuilder
public extension Array where Element == String {
    /// Returns a localized list of terms representing a conjunction or disjunction.
    func spm_localizedJoin(type: LocalizedJoinType) -> String {
        var result = ""

        for (i, item) in enumerated() {
            // Add the separator, if necessary.
            if i == count - 1 {
                switch count {
                case 1:
                    break
                case 2:
                    result += " \(type.rawValue) "
                default:
                    result += ", \(type.rawValue) "
                }
            } else if i != 0 {
                result += ", "
            }

            result += item
        }

        return result
    }
}


/// In memory implementation of WritableByteStream.
public final class BufferedOutputByteStream: _WritableByteStreamBase {

    /// Contents of the stream.
    private var contents = [UInt8]()

    public init() {
        // We disable the buffering of the underlying _WritableByteStreamBase as
        // we are explicitly buffering the whole stream in memory
        super.init(buffered: false)
    }

    /// The contents of the output stream.
    ///
    /// - Note: This implicitly flushes the stream.
    public var bytes: ByteString {
        flush()
        return ByteString(contents)
    }

    /// The current offset within the output stream.
    override public final var position: Int {
        return contents.count
    }

    override final func flushImpl() {
        // Do nothing.
    }

    override final func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        contents += bytes
    }
    override final func writeImpl(_ bytes: ArraySlice<UInt8>) {
        contents += bytes
    }

    override final func closeImpl() throws {
        // Do nothing. The protocol does not require to stop receiving writes, close only signals that resources could
        // be released at this point should we need to.
    }
}

/// Represents a stream which is backed to a file. Not for instantiating.
public class FileOutputByteStream: _WritableByteStreamBase {

    public override final func closeImpl() throws {
        flush()
        try fileCloseImpl()
    }

    /// Closes the file flushing any buffered data.
    func fileCloseImpl() throws {
        fatalError("fileCloseImpl() should be implemented by a subclass")
    }
}

/// Implements file output stream for local file system.
public final class LocalFileOutputByteStream: FileOutputByteStream {

    /// The pointer to the file.
    let filePointer: FILEPointer

    /// Set to an error value if there were any IO error during writing.
    private var error: FileSystemError?

    /// Closes the file on deinit if true.
    private var closeOnDeinit: Bool

    /// Path to the file this stream should operate on.
    private let path: URL?

    /// Instantiate using the file pointer.
    public init(filePointer: FILEPointer, closeOnDeinit: Bool = true, buffered: Bool = true) throws {
        self.filePointer = filePointer
        self.closeOnDeinit = closeOnDeinit
        self.path = nil
        super.init(buffered: buffered)
    }

    /// Opens the file for writing at the provided path.
    ///
    /// - Parameters:
    ///     - path: Path to the file this stream should operate on.
    ///     - closeOnDeinit: If true closes the file on deinit. clients can use
    ///                      close() if they want to close themselves or catch
    ///                      errors encountered during writing to the file.
    ///                      Default value is true.
    ///     - buffered: If true buffers writes in memory until full or flush().
    ///                 Otherwise, writes are processed and flushed immediately.
    ///                 Default value is true.
    ///
    /// - Throws: FileSystemError
    public init(_ path: URL, closeOnDeinit: Bool = true, buffered: Bool = true) throws {
        guard let filePointer = fopen(path.path, "wb") else {
            throw FileSystemError(errno: errno, path)
        }
        self.path = path
        self.filePointer = filePointer
        self.closeOnDeinit = closeOnDeinit
        super.init(buffered: buffered)
    }

    deinit {
        if closeOnDeinit {
            fclose(filePointer)
        }
    }

    func errorDetected(code: Int32?) {
        if let code = code {
            error = .init(.ioError(code: code), path)
        } else {
            error = .init(.unknownOSError, path)
        }
    }

    override final func writeImpl<C: Collection>(_ bytes: C) where C.Iterator.Element == UInt8 {
        // FIXME: This will be copying bytes but we don't have option currently.
        var contents = [UInt8](bytes)
        while true {
            let n = fwrite(&contents, 1, contents.count, filePointer)
            if n < 0 {
                if errno == EINTR { continue }
                errorDetected(code: errno)
            } else if n != contents.count {
                errorDetected(code: nil)
            }
            break
        }
    }

    override final func writeImpl(_ bytes: ArraySlice<UInt8>) {
        bytes.withUnsafeBytes { bytesPtr in
            while true {
                let n = fwrite(bytesPtr.baseAddress, 1, bytesPtr.count, filePointer)
                if n < 0 {
                    if errno == EINTR { continue }
                    errorDetected(code: errno)
                } else if n != bytesPtr.count {
                    errorDetected(code: nil)
                }
                break
            }
        }
    }

    override final func flushImpl() {
        fflush(filePointer)
    }

    override final func fileCloseImpl() throws {
        defer {
            fclose(filePointer)
            // If clients called close we shouldn't call fclose again in deinit.
            closeOnDeinit = false
        }
        // Throw if errors were found during writing.
        if let error = error {
            throw error
        }
    }
}

public struct FileSystemError: Error, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Access to the path is denied.
        ///
        /// This is used when an operation cannot be completed because a component of
        /// the path cannot be accessed.
        ///
        /// Used in situations that correspond to the POSIX EACCES error code.
        case invalidAccess

        /// IO Error encoding
        ///
        /// This is used when an operation cannot be completed due to an otherwise
        /// unspecified IO error.
        case ioError(code: Int32)

        /// Is a directory
        ///
        /// This is used when an operation cannot be completed because a component
        /// of the path which was expected to be a file was not.
        ///
        /// Used in situations that correspond to the POSIX EISDIR error code.
        case isDirectory

        /// No such path exists.
        ///
        /// This is used when a path specified does not exist, but it was expected
        /// to.
        ///
        /// Used in situations that correspond to the POSIX ENOENT error code.
        case noEntry

        /// Not a directory
        ///
        /// This is used when an operation cannot be completed because a component
        /// of the path which was expected to be a directory was not.
        ///
        /// Used in situations that correspond to the POSIX ENOTDIR error code.
        case notDirectory

        /// Unsupported operation
        ///
        /// This is used when an operation is not supported by the concrete file
        /// system implementation.
        case unsupported

        /// An unspecific operating system error at a given path.
        case unknownOSError

        /// File or folder already exists at destination.
        ///
        /// This is thrown when copying or moving a file or directory but the destination
        /// path already contains a file or folder.
        case alreadyExistsAtDestination

        /// If an unspecified error occurs when trying to change directories.
        case couldNotChangeDirectory

        /// If a mismatch is detected in byte count when writing to a file.
        case mismatchedByteCount(expected: Int, actual: Int)
    }

    /// The kind of the error being raised.
    public let kind: Kind

    /// The absolute path to the file associated with the error, if available.
    public let path: URL?

    public init(_ kind: Kind, _ path: URL? = nil) {
        self.kind = kind
        self.path = path
    }
}

extension FileSystemError: CustomNSError {
    public var errorUserInfo: [String : Any] {
        return [NSLocalizedDescriptionKey: "\(self)"]
    }
}

#if canImport(Darwin)

public extension FileSystemError {
    init(errno: Int32, _ path: URL) {
        switch errno {
        case Darwin.EACCES:
            self.init(.invalidAccess, path)
        case Darwin.EISDIR:
            self.init(.isDirectory, path)
        case Darwin.ENOENT:
            self.init(.noEntry, path)
        case Darwin.ENOTDIR:
            self.init(.notDirectory, path)
        default:
            self.init(.ioError(code: errno), path)
        }
    }
}



/// Public stdout stream instance.
public var stdoutStream: ThreadSafeOutputByteStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
    filePointer: Darwin.stdout,
    closeOnDeinit: false))

/// Public stderr stream instance.
public var stderrStream: ThreadSafeOutputByteStream = try! ThreadSafeOutputByteStream(LocalFileOutputByteStream(
    filePointer: Darwin.stderr,
    closeOnDeinit: false))
#endif

