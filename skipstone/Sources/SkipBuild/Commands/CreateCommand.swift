import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct CreateCommand: StreamingCommand, ToolOptionsCommand, CreateOptionsCommand {
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

            var firstPrompt = true
            while true {
                cout(firstPrompt ? "Enter selection (default: \(defaultCase.name)) [1..\(prompt.allCases.count)] " : "Please enter a value between 1 and \(prompt.allCases.count) ", newLine: false)
                firstPrompt = false
                let input = readLine(strippingNewline: true) ?? "\(defaultCaseIndex)"
                let index = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultCaseIndex : Int(input)
                guard let index, index > 0, index <= prompt.allCases.count else {
                    continue
                }
                return Array(prompt.allCases)[index - 1]
            }
        }

        func prompt(_ message: String, validate: (String) -> String?) -> String {
            var invalidMessage: String? = nil
            while true {
                cout((invalidMessage ?? message) + ": ", newLine: false)
                guard let input = readLine(strippingNewline: true) else {
                    continue
                }
                invalidMessage = validate(input)
                if invalidMessage == nil {
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
                case .fuse: return "Skip Fuse"
                case .lite: return "Skip Lite"
                }
            }

            var desc: String? {
                switch self {
                case .fuse: return "natively compiled project"
                case .lite: return "transpiled project"
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

        let moduleName = prompt("Enter the CamelCase name of the \(projectType.name) module", validate: isValidModuleName)

        var moduleNames = [moduleName]
        while true {
            let extraModuleName = prompt("Optionally enter additional module names", validate: {
                moduleNames.contains($0) ? "Module name already exists" : $0.isEmpty ? nil : isValidModuleName($0)
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
                moduleMode = prompt("Enable Kotlin compatibility for native module", defaultValue: createOptions.kotlincompat) ? .kotlincompat : .native
            }
        }

        let freeProject = prompt("Create a free open-source project?", defaultValue: createOptions.free)
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

        let openXcode = prompt("Open the \(isApp ? "Xcode" : "Swift") project after initialization?", defaultValue: true)


        let modules = try moduleNames.map {
            try PackageModule(parse: $0)
        }

        // auto-install the Android SDK if we are selecting a native project
        if installNativeSDK {
            try await installAndroidSDK(version: AndroidSDKInstallCommand.defaultAndroidSDKVersion, reinstall: false, with: out)
        }

        let dir = URL(fileURLWithPath: self.createOptions.dir ?? projectName, isDirectory: true)

        let (createdURL, project, _) = try await initSkipProject(
            baseName: projectName,
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
            chain: createOptions.chain,
            gitRepo: gitRepo,
            free: freeProject,
            appfair: nil,
            zero: createOptions.zero,
            appid: appid,
            icon: nil,
            version: createOptions.swiftVersion,
            swiftVersion: nativeMode.swiftVersion,
            nativeMode: nativeMode,
            moduleMode: moduleMode,
            moduleTests: createTests ?? true,
            github: gitRepo,
            fastlane: fastlane,
            validatePackage: createOptions.validatePackage,
            packageResolved: nil,
            apk: isApp,
            ipa: isApp,
            with: out
        )

        let _ = createdURL

        if openXcode {
            let projectPath = isApp ? project.darwinProjectFolder : project.packageSwift
            try await run(with: out, "Opening Xcode project", ["open", projectPath.path])
        }

        cout("Project successfully created at \(createdURL.path)")
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
