// Copyright 2023 Skip
//
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org
import Foundation
import SkipDrive

/// The name of the app's Swift target in the Package.swift
let appName = "AppUI"

/// The name of the SPM package in which this app is bundled
let packageName = "skipapp"

/// Front-end to the `gradle` build tool for Skip projects.
#if os(macOS)
@available(macOS 13, macCatalyst 16, *)
@main public struct SkipGradleMain : GradleHarness {
    static func main() async throws {
        do {
            //print("Running skipgradle with arguments:", CommandLine.arguments)
            let gradle = SkipGradleMain()

            // the build is run as a script at the end of the Build Phases
            print("Running Gradle build for app…")
            try await gradle.gradleExec(appName: appName, packageName: packageName, arguments: Array(CommandLine.arguments.dropFirst(1)))
        } catch {
            print("Error launching: \(error)")
            //print("\(#file):\(#line):\(#column): error: AppDroid: \(error.localizedDescription)")
            //throw error // results in a fatalError
            exit(1)
        }
    }
}
#endif

