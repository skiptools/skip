// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CreateCommand: StreamingCommand, ToolchainOptionsCommand, CreateOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new Skip project interactively",
        discussion: """
Create a new project by following a series of interactive prompts.
""",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Toolchain Options")
    var toolchainOptions: ToolchainOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    struct Output : MessageEncodable {
        let message: String
        func message(term: Term) -> String? {
            message
        }
    }

    func performCommand(with out: MessageQueue) async throws {
        cout("Welcome to Skip \(skipVersion)!")
        cout("")

        func cout(_ msg: String, newLine: Bool = true) {
            //await out.yield(Output(message: msg))
            if newLine {
                print(msg)
            } else {
                print(msg, terminator: "")
                stdoutStream.flush()
            }
        }

        func prompt<T: PromptOption>(_ message: String, prompt: T.Type) -> T {
            cout(message + ":")
            let defaultCase = prompt.defaultCase
            var defaultCaseIndex = 0
            for (i, p) in prompt.allCases.enumerated() {
                let index = i + 1
                if p == defaultCase { defaultCaseIndex = index }
                var pmpt = "  \(index): \(p.name)"
                if let desc = p.desc {
                    pmpt += ": \(desc)"
                }
                cout(pmpt)
            }

            while true {
                cout("Enter selection (default: \(defaultCase.name)) [1..\(prompt.allCases.count)] ", newLine: false)
                let input = readLine(strippingNewline: true) ?? "\(defaultCaseIndex)"
                let index = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultCaseIndex : Int(input)
                guard let index, index > 0, index <= prompt.allCases.count else {
                    cout(Term.ansi.red("Please enter a value between 1 and \(prompt.allCases.count)"))
                    continue
                }
                return Array(prompt.allCases)[index - 1]
            }
        }

        func prompt(_ message: String, validate: (String) -> String?) -> String {
            while true {
                cout(message + ": ", newLine: false)
                guard let input = readLine(strippingNewline: true) else {
                    continue
                }
                if let invalidMessage = validate(input) {
                    cout(Term.ansi.red(invalidMessage))
                } else {
                    return input
                }
            }
        }

        func prompt(_ message: String, defaultValue: Bool) -> Bool {
            cout(message + " (y/n) [\(defaultValue ? "y" : "n")]: ", newLine: false)
            while true {
                guard let input = readLine(strippingNewline: true), !input.isEmpty else {
                    return defaultValue
                }
                if input.lowercased().hasPrefix("y") {
                    return true
                }
                if input.lowercased().hasPrefix("n") {
                    return false
                }
                continue
            }
        }


        enum ProjectTypeOption : PromptOption, CaseIterable {
            case app
            case library

            var name: String {
                switch self {
                case .app: return "App"
                case .library: return "Library"
                }
            }

            var desc: String? {
                switch self {
                case .app: return "mobile application for Android and iOS"
                case .library: return "library project with one or more modules"
                }
            }
        }

        enum ProjectModeOption : PromptOption, CaseIterable {
            case fuse
            case lite

            var name: String {
                switch self {
                case .lite: return "Skip Lite"
                case .fuse: return "Skip Fuse"
                }
            }

            var desc: String? {
                switch self {
                case .lite: return "transpiled project"
                case .fuse: return "natively compiled project"
                }
            }
        }

        let projectType = prompt("Select type of project to create", prompt: ProjectTypeOption.self)
        let isApp = projectType == .app
        let skipMode = prompt("Select the mode of the project", prompt: ProjectModeOption.self)
        let nativeMode: NativeMode = isApp ? (skipMode == .fuse ? .nativeApp : []) : (skipMode == .fuse ? .nativeModel : [])

        let projectName = prompt("Enter the project-name for the \(projectType.name)", validate: {
            if let invalidProjectName = isValidProjectName($0) {
                return invalidProjectName
            }
            if FileManager.default.fileExists(atPath: "\(self.createOptions.dir ?? ".")/\($0)") {
                return "Project folder with this name already exists"
            }
            return nil
        })

        var moduleNames: [String] = []

        func isValidProjectModuleName(_ moduleName: String) -> String? {
            if let invalidMessage = isValidModuleName(moduleName) {
                return invalidMessage
            }
            if moduleNames.contains(moduleName) {
                return "The module name \"\(moduleName)\" is already used"
            }
            if moduleName.lowercased() == projectName.lowercased() {
                return "The module name \"\(moduleName)\" must be different from the project name"
            }
            return nil
        }
        let moduleName = prompt("Enter the CamelCase name of the \(projectType.name) module", validate: isValidProjectModuleName)

        moduleNames += [moduleName]

        while true {
            let extraModuleName = prompt("Optionally enter additional module names", validate: {
                moduleNames.contains($0) ? "Module name already exists" : $0.isEmpty ? nil : isValidProjectModuleName($0)
            })
            if extraModuleName.isEmpty {
                break
            } else {
                moduleNames.append(extraModuleName)
            }
        }

        var appid: String? = nil
        if isApp {
            appid = prompt("Enter the app bundle identifier", validate: isValidBundleIdentifier)
        }

        var moduleMode: ModuleMode = skipMode == .fuse ? .native : .transpiled

        var createTests = createOptions.moduleTests
        if !isApp {
            createTests = prompt("Create test cases", defaultValue: createTests ?? true)
            if skipMode == .fuse {
                moduleMode = prompt("Enable Kotlin compatibility for native module", defaultValue: createOptions.kotlincompat) ? .kotlincompat : .nativeBridged
            }
        }

        let freeProject = prompt("Create an open-source \(isApp ? "app" : "library")?", defaultValue: createOptions.free)
        let appFairProject = !isApp || !freeProject ? false : prompt("Create an App Fair Project?", defaultValue: createOptions.appfair)

        let gitRepo = prompt("Initialize git repository for the project?", defaultValue: createOptions.gitRepo)

        var fastlane = false
        if isApp {
            fastlane = prompt("Initialize a Fastlane configuration for the project?", defaultValue: createOptions.fastlane)
        }

        let buildProject = prompt("Pre-build the project?", defaultValue: true)

        var runTests = false
        if !isApp && createTests == true {
            runTests = prompt("Run project test cases?", defaultValue: true)
        }

        var installNativeSDK = false
        if skipMode == .fuse {
            installNativeSDK = prompt("Install the Swift Android SDK?", defaultValue: true)
        }

        #if os(macOS)
        let openXcode = prompt("Open the \(isApp ? "Xcode" : "Swift") project after initialization?", defaultValue: true)
        #else
        let openXcode = false // TODO: maybe prompt to open in another editor like vscode?
        #endif

        let modules = try moduleNames.map {
            try PackageModule(parse: $0)
        }

        // auto-install the Android SDK if we are selecting a native project
        if installNativeSDK {
            try await installAndroidSDK(version: AndroidSDKInstallCommand.defaultAndroidSDKVersion, ndkVersion: AndroidSDKInstallCommand.defaultAndroidNDKVersion, reinstall: false, selfTest: false, with: out)
        }

        let dir = URL(fileURLWithPath: self.createOptions.dir ?? projectName, isDirectory: true)

        var options = createOptions.projectOptionValues(projectName: projectName)
        // override with options specified interactively
        options.gitRepo = gitRepo
        options.free = freeProject
        options.appfair = appFairProject
        options.fastlane = fastlane

        await withLogStream(with: out) {
            let (createdURL, project, _) = try await initSkipProject(
                options: options,
                modules: modules,
                resourceFolder: "Resources",
                dir: dir,
                verify: false,
                configuration: .debug,
                build: buildProject,
                test: runTests,
                returnHashes: false,
                messagePrefix: nil,
                showTree: createOptions.showTree,
                app: isApp,
                appid: appid,
                icon: nil,
                version: "1.0.0",
                nativeMode: nativeMode,
                moduleMode: moduleMode,
                moduleTests: createTests ?? true,
                validatePackage: createOptions.validatePackage,
                packageResolved: nil,
                apk: buildProject && isApp,
                ipa: buildProject && isApp,
                with: out
            )

            if openXcode {
                let projectPath = isApp ? project.darwinProjectFolder : project.packageSwift
                try await run(with: out, "Opening Xcode project", ["open", projectPath.path])
            }

            cout("Project successfully created at \(createdURL.path)")
        }
    }
}

protocol PromptOption : Equatable, CaseIterable {
    static var defaultCase: Self { get }
    var name: String { get }
    var desc: String? { get }
}

extension PromptOption {
    static var defaultCase: Self { allCases.first! }
    var desc: String? { nil }
}
