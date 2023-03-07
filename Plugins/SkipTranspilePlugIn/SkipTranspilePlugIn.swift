import Foundation
import PackagePlugin

/// Build plugin to do pre-work like emit warnings about incompatible Swift before transpiling with Skip.
@main struct SkipTranspilePlugIn: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let tool = try context.tool(named: "skiptool")
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
        return [
            .buildCommand(displayName: "Skip Transpile Build \(target.name)", executable: tool.path, arguments: args + []),
        ]
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
