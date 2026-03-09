// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import SkipBuild
import TSCBasic
import ArgumentParser

// MARK: - Test Message Command

/// A test command that conforms to MessageCommand and ToolOptionsCommand for use in validators
///
/// Note: To create an instance, use `try TestMessageCommand.parse([])` in your test.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct TestMessageCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "test-message-command",
        abstract: "Test command for validators",
        shouldDisplay: false
    )

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    func performCommand(with out: MessageQueue) async throws {
        // Test command doesn't do anything by default
        // It's used as a vehicle to access the run() method for executing sub-commands
    }
}

// MARK: - Mock Environment Helpers

/// Helper to create temporary directories with mock scripts for testing
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct MockEnvironment {
    let tempDir: String
    let homeDir: String
    let homebrewPrefix: String
    let androidHome: String

    /// Path to the Homebrew OpenJDK installation (used by validateJava)
    var javaHome: String {
        "\(homebrewPrefix)/opt/java"
    }

    /// Path to the emulator binary (ANDROID_HOME/emulator/emulator)
    var emulatorPath: String {
        "\(androidHome)/emulator/emulator"
    }

    init() throws {
        let baseTemp = "\(FileManager.default.temporaryDirectory.path)/skip-tests-\(UUID().uuidString)"

        self.tempDir = baseTemp
        self.homeDir = "\(baseTemp)/home"
        self.homebrewPrefix = "\(baseTemp)/opt/homebrew"
        self.androidHome = "\(homeDir)/Library/Android/sdk"

        // Create directories
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: homeDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: homebrewPrefix, withIntermediateDirectories: true)

        try createMockScript(at: "\(javaHome)/bin/java", content: """
            echo 'openjdk version "17.0.0" 2024-01-01' >&2
            exit 0
            """)
    }
    
    /// Creates a mock executable script at the given path
    func createMockScript(at path: String, content: String) throws {
        let parentDir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        
        let scriptContent = "#!/bin/bash\n" + content
        try scriptContent.write(toFile: path, atomically: true, encoding: .utf8)
        
        if FileManager.default.fileExists(atPath: path) {
            _ = chmod(path, 0o755)
        }
    }
    
    /// Creates a mock executable script that echoes the given string and exits 0
    func createMockScript(at path: String, echoing: String) throws {
        try createMockScript(at: path, content: """
            echo "\(echoing)"
            exit 0
            """)
    }
    
    /// Creates a mock bootstrap sdkmanager at homebrew prefix that installs cmdline-tools to androidHome
    /// when invoked as: sdkmanager --sdk_root=<androidHome> "cmdline-tools;latest"
    /// Also creates bootstrap avdmanager and emulator, then copies them to their installed locations
    func createMockBootstrapSdkmanager() throws {
        // Create bootstrap avdmanager and emulator that will be copied during installation
        let bootstrapAvdmanager = "\(homebrewPrefix)/bin/avdmanager"
        try createMockScript(at: bootstrapAvdmanager, echoing: "Android Virtual Device created successfully")

        let bootstrapEmulator = "\(homebrewPrefix)/share/android-commandlinetools/emulator/emulator"
        try createMockScript(at: bootstrapEmulator, echoing: "")

        let sdkmanagerPath = "\(homebrewPrefix)/bin/sdkmanager"
        let cmdlineToolsPath = "\(androidHome)/cmdline-tools/latest/bin"
        let installedSdkmanager = "\(cmdlineToolsPath)/sdkmanager"
        let installedAvdmanager = "\(cmdlineToolsPath)/avdmanager"
        let emulatorPath = "\(androidHome)/emulator/emulator"

        try createMockScript(at: sdkmanagerPath, content: """
            if [ "$1" = "--version" ]; then
                echo "20.0"
            elif [ "$1" = "--verbose" ] && [ "$2" = "--install" ] && [[ "$3" == --sdk_root=* ]] && [ "$4" = "cmdline-tools;latest" ]; then
                mkdir -p \(cmdlineToolsPath)

                # Create installed sdkmanager that just echoes version
                echo '#!/bin/bash' > \(installedSdkmanager)
                echo 'echo "20.0"' >> \(installedSdkmanager)
                chmod +x \(installedSdkmanager)

                # Copy bootstrap avdmanager to installed location
                cp \(bootstrapAvdmanager) \(installedAvdmanager)

                # Copy bootstrap emulator to installed location
                mkdir -p \(androidHome)/emulator
                cp \(bootstrapEmulator) \(emulatorPath)
            fi
            exit 0
            """)
    }
    
    /// Returns environment variables configured for testing with mock scripts
    func environment(additional: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = homeDir
        env["HOMEBREW_PREFIX"] = homebrewPrefix
        env["ANDROID_HOME"] = androidHome
        env["PATH"] = "\(homebrewPrefix)/bin:/usr/bin:/bin"

        for (key, value) in additional {
            env[key] = value
        }

        return env
    }
    
    /// Cleans up the temporary directory
    func cleanup() {
        try? FileManager.default.removeItem(atPath: tempDir)
    }
}

// MARK: - XCTest Helpers

extension XCTestCase {
    /// Asserts that an async expression throws an error
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @escaping () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line,
        _ errorHandler: @escaping (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error but none was thrown", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}

// MARK: - Test Message Queue Helper

/// Helper to run a validator with a collecting queue, returning both the result and the messages
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func runValidator<T>(
    _ operation: (MessageQueue) async throws -> T
) async throws -> (result: T, messages: [MessageBlock]) {
    let (_, continuation) = MessageStream.makeStream()
    let queue = MessageQueue(retain: true, continuation: continuation)

    let result = try await operation(queue)

    // Extract message blocks from the queue's elements
    let elements = await queue.elements
    let messages: [MessageBlock] = elements.compactMap {
        switch $0 {
        case .success(let element as MessageBlock): return element
        default: return nil
        }
    }

    return (result, messages)
}

// MARK: - AndroidEmulatorSetupTests

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
final class AndroidEmulatorSetupTests: XCTestCase {
    
    var mockEnv: MockEnvironment!
    
    override func setUp() async throws {
        try await super.setUp()
        mockEnv = try MockEnvironment()
    }
    
    override func tearDown() async throws {
        mockEnv?.cleanup()
        mockEnv = nil
        ProcessInfo.mockEnvironment = nil
        try await super.tearDown()
    }
    
    // MARK: - cmdline-tools Validation Tests

    /// Missing cmdline-tools with bootstrap available
    /// The bootstrap sdkmanager script creates the cmdline-tools when executed
    func testCmdlineToolsBootstrap() async throws {
        // Create Android SDK without cmdline-tools
        let androidHome = mockEnv.androidHome

        // Create bootstrap sdkmanager at homebrew location that installs cmdline-tools when run
        try mockEnv.createMockBootstrapSdkmanager()

        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try TestMessageCommand.parse([])

        let (result, messages) = try await runValidator { queue in
            try await ensureCmdlineTools(
                command: command,
                out: queue
            )
        }

        XCTAssertTrue(result.wasBootstrapped)
        XCTAssertEqual(result.sdkmanagerPath, "\(androidHome)/cmdline-tools/latest/bin/sdkmanager")
        // StreamingCommand.run() generates message blocks with timing info for each command run,
        // plus ensureCmdlineTools writes its own messages
        // Should have more messages now due to StreamingCommand.run() timing messages
        XCTAssertGreaterThanOrEqual(messages.count, 2)
    }

    /// Bootstrap installation fails - cmdline-tools still not present after installation
    /// The bootstrap script runs but doesn't create cmdline-tools (simulating a failed install)
    func testCmdlineToolsBootstrapFails() async throws {
        // Create bootstrap sdkmanager at homebrew location that does NOT create cmdline-tools
        // The bootstrap is invoked as: sdkmanager --sdk_root=<androidHome> "cmdline-tools;latest"
        // (simulating a failed bootstrap installation that doesn't create the files)
        let bootstrapSdkmanager = "\(mockEnv.homebrewPrefix)/bin/sdkmanager"
        try? mockEnv.createMockScript(at: bootstrapSdkmanager, echoing: "20.0")

        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try TestMessageCommand.parse([])

        await XCTAssertThrowsErrorAsync(
            { _ = try await runValidator { queue in
                try await ensureCmdlineTools(
                    command: command,
                    out: queue
                )
            }}
        ) { error in
            XCTAssertTrue(error is CmdlineToolsBootstrapFailedError)
        }
    }

    /// Existing cmdline-tools validated successfully
    func testCmdlineToolsValidationSucceedsWhenPresent() async throws {
        // Create Android SDK with cmdline-tools
        let androidHome = mockEnv.androidHome

        let sdkmanagerPath = "\(androidHome)/cmdline-tools/latest/bin/sdkmanager"
        try mockEnv.createMockScript(at: sdkmanagerPath, echoing: "20.0")

        let emulatorPath = "\(androidHome)/emulator/emulator"
        try mockEnv.createMockScript(at: emulatorPath, echoing: "")

        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try TestMessageCommand.parse([])

        let (result, messages) = try await runValidator { queue in
            try await ensureCmdlineTools(
                command: command,
                out: queue
            )
        }

        XCTAssertFalse(result.wasBootstrapped)
        XCTAssertEqual(result.version, "20.0")
        XCTAssertEqual(result.sdkmanagerPath, sdkmanagerPath)
        // StreamingCommand.run() generates a message block with timing info,
        // and ensureCmdlineTools adds its own message
        XCTAssertGreaterThanOrEqual(messages.count, 1)
        XCTAssertEqual(messages.first?.status, MessageBlock.Status.pass)
    }

    /// No sdkmanager found anywhere
    func testCmdlineToolsNotFoundAnywhereFails() async throws {
        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try TestMessageCommand.parse([])

        await XCTAssertThrowsErrorAsync(
            { _ = try await runValidator { queue in
                try await ensureCmdlineTools(
                    command: command,
                    out: queue
                )
            }}
        ) { error in
            XCTAssertTrue(error is CmdlineToolsNotFoundError)
        }
    }

    // MARK: - AndroidHomeInstallCommand Tests

    /// Test AndroidHomeInstallCommand sets up the Android SDK
    func testAndroidHomeInstallCommand() async throws {
        // Ensure ANDROID_HOME doesn't exist yet (will be created by command)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mockEnv.androidHome))

        // Create bootstrap sdkmanager that will install cmdline-tools
        try mockEnv.createMockBootstrapSdkmanager()

        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try AndroidHomeInstallCommand.parse([])

        let stream = MessageStream { continuation in
            Task {
                let messageQueue = MessageQueue(retain: true, continuation: continuation)
                do {
                    try await command.performCommand(with: messageQueue)
                    await messageQueue.finish()
                } catch {
                    await messageQueue.finish(throwing: error)
                }
            }
        }

        var messages: [String] = []
        for try await message in stream {
            if let msg = message.message(term: .plain) {
                messages.append(msg)
            }
        }

        XCTAssertGreaterThan(messages.count, 0, "performCommand should generate messages")

        // Verify ANDROID_HOME was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: mockEnv.androidHome))

        // Verify Java validation ran
        let javaMessages = messages.filter { $0.contains("JAVA") }
        XCTAssertGreaterThan(javaMessages.count, 0, "Java validation should run")

        // Verify ANDROID_HOME creation was reported
        let androidHomeMessages = messages.filter { $0.contains("ANDROID_HOME") || $0.contains("Created") }
        XCTAssertGreaterThan(androidHomeMessages.count, 0, "ANDROID_HOME setup should run")
    }

    // MARK: - Integration Tests

    /// Test AndroidEmulatorCreateCommand.performCommand validates environment
    /// Now requires pre-configured Android SDK (no bootstrapping)
    func testAndroidEmulatorCreateCommandPerformCommand() async throws {
        let androidHome = mockEnv.androidHome

        // Create a fully configured Android SDK (not just a bootstrap one)
        // This includes: cmdline-tools, sdkmanager, avdmanager, and emulator
        try FileManager.default.createDirectory(atPath: androidHome, withIntermediateDirectories: true)

        let cmdlineToolsPath = "\(androidHome)/cmdline-tools/latest/bin"
        let sdkmanagerPath = "\(cmdlineToolsPath)/sdkmanager"
        let avdmanagerPath = "\(cmdlineToolsPath)/avdmanager"
        let emulatorPath = "\(androidHome)/emulator/emulator"

        // Create sdkmanager that responds to --version
        try mockEnv.createMockScript(at: sdkmanagerPath, content: """
            if [ "$1" = "--version" ]; then
                echo "20.0"
            fi
            exit 0
            """)

        // Create avdmanager that responds to create command
        try mockEnv.createMockScript(at: avdmanagerPath, echoing: "Android Virtual Device created successfully")

        // Create emulator that lists AVDs
        try mockEnv.createMockScript(at: emulatorPath, echoing: "")

        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try AndroidEmulatorCreateCommand.parse([])

        let stream = MessageStream { continuation in
            Task {
                let messageQueue = MessageQueue(retain: true, continuation: continuation)
                do {
                    try await command.performCommand(with: messageQueue)
                    await messageQueue.finish()
                } catch {
                    await messageQueue.finish(throwing: error)
                }
            }
        }

        var messages: [String] = []
        for try await message in stream {
            if let msg = message.message(term: .plain) {
                messages.append(msg)
            }
        }

        XCTAssertGreaterThan(messages.count, 0, "performCommand should generate messages")
        let androidHomeMessages = messages.filter { $0.contains("ANDROID_HOME") }
        XCTAssertGreaterThan(androidHomeMessages.count, 0, "ANDROID_HOME validation should run")
    }

    /// Test AndroidEmulatorCreateCommand fails when cmdline-tools not installed
    func testAndroidEmulatorCreateCommandFailsWhenCmdlineToolsMissing() async throws {
        ProcessInfo.mockEnvironment = mockEnv.environment()

        let command = try AndroidEmulatorCreateCommand.parse([])

        await XCTAssertThrowsErrorAsync(
            { _ = try await runValidator { queue in
                try await command.performCommand(with: queue)
            }}
        ) { error in
            XCTAssertTrue(error is CmdlineToolsNotFoundError, "Expected CmdlineToolsNotFoundError but got \(type(of: error))")
        }
    }
}
