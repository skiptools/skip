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
        
        return [
            .prebuildCommand(displayName: "Skip Transpile Prebuild \(target.name)", executable: tool.path, arguments: ["version"], outputFilesDirectory: outputFolder),
            .buildCommand(displayName: "Skip Transpile Build \(target.name)", executable: tool.path, arguments: ["version"]),
        ]
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
