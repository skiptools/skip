import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipTranspilePlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "skiptool")
        let outputFolder = context.pluginWorkDirectory
        let pkg = context.package

        let kotlinSuffix = "Kotlin"
        let testSuffix = "Tests"
        let isTest = target.name.hasSuffix(testSuffix)

        if isTest {
            // Known issue with SPM in Xcode: we cannot have a depencency from one testTarget to another, or we hit the error:
            // Enable to resolve build file: XCBCore.BuildFile (The workspace has a reference to a missing target with GUID 'PACKAGE-TARGET:CrossSQLTests')
            return []
        }

        if !target.name.hasSuffix(kotlinSuffix + (isTest ? testSuffix : "")) {
            struct BadKotlinTargetName : LocalizedError { let errorDescription: String? }
            throw BadKotlinTargetName(errorDescription: "Target «\(target.name)» should have suffix «\(kotlinSuffix)»")
        }

        let expectedName = String(target.name.dropLast(kotlinSuffix.count + (isTest ? testSuffix.count : 0))) + (isTest ? testSuffix : "")

        guard let firstDependencyTarget = target.dependencies.first,
              case .target(let peerTarget) = firstDependencyTarget,
              peerTarget.name == expectedName else {
            struct MissingPeerTarget : LocalizedError { let errorDescription: String? }
            throw MissingPeerTarget(errorDescription: "Target «\(target.name)» should have initial dependency on «\(expectedName)»")
        }

        var args = ["version"]

        args += [
            "--module", peerTarget.name,
            "--folder", URL.moduleBuildFolder.path,
        ]



        // ### ENV: ["DIRHELPER_USER_DIR_SUFFIX": "com.apple.shortcuts.mac-helper", "TERM_PROGRAM": "Apple_Terminal", "XPC_FLAGS": "0x0", "TERM": "xterm-256color", "__CF_USER_TEXT_ENCODING": "0x1F5:0x0:0x0", "SHELL": "/bin/zsh", "SHLVL": "3", "CA_DEBUG_TRANSACTIONS": "1", "HOMEBREW_REPOSITORY": "/opt/homebrew", "_": "/usr/bin/open", "OLDPWD": "/opt/src/github/skiptools/SkipSource", "JAVA_HOME": "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home", "HOME": "/Users/marc", "HOMEBREW_PREFIX": "/opt/homebrew", "TMPDIR": "/var/folders/zl/wkdjv4s1271fbm6w0plzknkh0000gn/T/com.apple.shortcuts.mac-helper/", "MANPATH": "/opt/homebrew/share/man::", "XPC_SERVICE_NAME": "application.com.apple.dt.Xcode.161120899.161686715", "__CFBundleIdentifier": "com.apple.dt.Xcode", "ANDROID_HOME": "/Users/marc/Library/Android/sdk", "PWD": "/opt/src/github/skiptools/SkipSource", "WORDCHARS": "*?_-.[]~=&;!#$%^(){}<>", "GREP_OPTIONS": "--color=auto", "TERM_PROGRAM_VERSION": "447", "USER": "marc", "COMMAND_MODE": "unix2003", "HOMEBREW_CELLAR": "/opt/homebrew/Cellar", "LD_LIBRARY_PATH": "/Applications/Xcode.app/Contents/Developer/../SharedFrameworks/", "INFOPATH": "/opt/homebrew/share/info:", "LANG": "en_US.UTF-8", "PATH": "/Applications/Xcode.app/Contents/Developer/usr/bin:/Users/marc/.gem/ruby/2.6.0/bin:/usr/local/lib/ruby/gems/3.0.0/bin:/usr/local/opt/ruby/bin:/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/Library/Apple/usr/bin:/Users/marc/bin", "EDITOR": "vi", "CA_ASSERT_MAIN_THREAD_TRANSACTIONS": "1", "GPG_TTY": "/dev/ttys004", "TERM_SESSION_ID": "52E4B0F7-52C8-4729-B568-1BF0BEFC4759", "SSH_AUTH_SOCK": "/private/tmp/com.apple.launchd.N8kQx4AM4T/Listeners", "LOGNAME": "marc", "MallocSpaceEfficient": "1"]
        print("### ENV:", ProcessInfo.processInfo.environment)

        // ### ARGS: ["/Users/marc/Library/Developer/Xcode/DerivedData/Skip-emjrydmkshgulsfvsxycpsqcflgp/SourcePackages/plugins/SkipTranspilePlugIn"]
        print("### ARGS:", CommandLine.arguments)

        print("### preparing build command with arguments:", args)

        // e.g.: ~/Library/Developer/Xcode/DerivedData/Skip-emjrydmkshgulsfvsxycpsqcflgp/SourcePackages/plugins/SkipTranspilePlugIn
        guard let arg0 = CommandLine.arguments.first else {
            struct MissingCommandError : LocalizedError { let errorDescription: String? }
            throw MissingCommandError(errorDescription: "Command missing initial argument")
        }

        let baseFolder = URL(fileURLWithPath: arg0, isDirectory: false)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let buildFolder = baseFolder.appendingPathComponent("Build", isDirectory: true)
        let productsFolder = buildFolder.appendingPathComponent("Products", isDirectory: true)

        #warning("FIXME: plugin is always compiled in release mode")
//        #if DEBUG
//        let debug = true
//        #else
//        let debug = false
//        #endif

        let debug = true
        let buildModeFolder = productsFolder.appendingPathComponent(debug ? "Debug" : "Release", isDirectory: true)
        let buildLocalFolder = productsFolder.appendingPathComponent(debug ? ".build/debug" : ".build/release", isDirectory: true)

        let peerBuildFolder = buildModeFolder.appendingPathComponent(peerTarget.name, isDirectory: true)

        print("### peerBuildFolder:", peerBuildFolder.path)
        print("### pluginWorkDirectory:", context.pluginWorkDirectory)


        var cmds: [Command]  = [
        ]

        cmds += [
            //.prebuildCommand(displayName: "Skip Transpile Build \(target.name)", executable: tool.path, arguments: args, outputFilesDirectory: context.pluginWorkDirectory),
        ]

        do {
            let args = [
//                "transpile",
                "version",
                "-v",
                "-E",
                "-o", "/private/tmp/skipversion.out"
            ]
            cmds += [
                .buildCommand(displayName: "Skip Transpile Build \(target.name)", executable: tool.path, arguments: args),
            ]
        }

        cmds += [
//            .buildCommand(displayName: "Swift Version", executable: try context.tool(named: "swift").path, arguments: ["-version"]),
//            .buildCommand(displayName: "Cat Etc Hosts", executable: try context.tool(named: "echo").path, arguments: ["XXX"]),
//            .buildCommand(displayName: "Issue Timestamp", executable: try context.tool(named: "sh").path, arguments: ["-c", ["touch", context.pluginWorkDirectory.string + "/" + "TIMESTAMP.txt"].joined(separator: " ")]),
//            .buildCommand(displayName: "Issue Timestamp", executable: try context.tool(named: "sh").path, arguments: ["-c", ["touch", "/tmp" + "/" + "TIMESTAMP.txt"].joined(separator: " ")]),
        ]

//        do {
//            let symbolGraphArgs = [
//                "symbolgraph-extract",
//                "-module-name", peerTarget.name,
//                "-include-spi-symbols",
//                "-skip-inherited-docs",
//                "-skip-synthesized-members",
//                "-output-dir", "/tmp/qqqq",
//                "-target", "arm64-apple-macosx13.0",
//                "-sdk", "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX13.1.sdk",
//                "-minimum-access-level", "private",
//                "-I", buildModeFolder.path,
//                "-I", buildLocalFolder.path,
//            ]
//
//            cmds += [
//                .buildCommand(displayName: "Skip Extract Symbols \(target.name)", executable: try context.tool(named: "swift").path, arguments: symbolGraphArgs),
//            ]
//        }

        return cmds
    }
}


extension URL {
    /// The folder where built modules will be placed.
    ///
    /// When running within Xcode, which will query the `__XCODE_BUILT_PRODUCTS_DIR_PATHS` environment.
    /// Otherwise, it assumes SPM's standard ".build" folder relative to the working directory.
    static var moduleBuildFolder: URL {
        // if we are running tests from Xcode, this environment variable should be set; otherwise, assume the .build folder for an SPM build
        let xcodeBuildFolder = ProcessInfo.processInfo.environment["__XCODE_BUILT_PRODUCTS_DIR_PATHS"] ?? ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] // also seems to be __XPC_DYLD_LIBRARY_PATH or __XPC_DYLD_FRAMEWORK_PATH; this will be something like ~/Library/Developer/Xcode/DerivedData/MODULENAME-bsjbchzxfwcrveckielnbyhybwdr/Build/Products/Debug


#if DEBUG
        let swiftBuildFolder = ".build/debug"
#else
        let swiftBuildFolder = ".build/release"
#endif

        return URL(fileURLWithPath: xcodeBuildFolder ?? swiftBuildFolder, isDirectory: true)
    }
}

//#if canImport(XcodeProjectPlugin)
//import XcodeProjectPlugin
//
//extension SkipTranspilePlugIn: XcodeBuildToolPlugin {
//    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
//    }
//}
//#endif
