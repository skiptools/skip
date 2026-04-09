// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(SkipDriveExternal)
import SkipDriveExternal

extension SBOMCreateCommand : GradleHarness { }
extension SBOMValidateCommand : GradleHarness { }
extension SBOMVerifyCommand : GradleHarness { }
extension VerifyCommand : GradleHarness { }
fileprivate let sbomCommandEnabled = true
#else
fileprivate let sbomCommandEnabled = false
#endif

// MARK: - Container Command

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct SBOMCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "sbom",
        abstract: "Generate and validate SPDX SBOM files for iOS and Android",
        discussion: """
        Commands for generating and validating Software Bill of Materials (SBOM) \
        in SPDX JSON format for Skip app projects.
        """,
        shouldDisplay: sbomCommandEnabled,
        subcommands: [
            SBOMCreateCommand.self,
            SBOMValidateCommand.self,
            SBOMVerifyCommand.self,
        ])
}

// MARK: - Create Subcommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct SBOMCreateCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Generate SPDX SBOM files for iOS and Android",
        usage: """
# generate SBOMs for both platforms
skip sbom create

# generate SBOM for iOS only
skip sbom create --ios

# generate SBOM for Android only
skip sbom create --android

# specify output directory
skip sbom create -d ./output

# link SBOMs into app Resources
skip sbom create --link-resource
""",
        discussion: """
Generate Software Bill of Materials (SBOM) in SPDX JSON format for a Skip app project. \
By default, generates SBOMs for both iOS (sbom-darwin-ios.spdx.json) and Android (sbom-linux-android.spdx.json). \
For iOS, dependencies are extracted from the SwiftPM Package.resolved file. \
For Android, the spdx-gradle-plugin is used to analyze Gradle dependencies.
""",
        shouldDisplay: sbomCommandEnabled)

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Output directory for SBOM files", valueName: "directory"))
    var dir: String?

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Flag(help: ArgumentHelp("Generate SBOM for iOS only"))
    var ios: Bool = false

    @Flag(help: ArgumentHelp("Generate SBOM for Android only"))
    var android: Bool = false

    @Flag(name: .long, help: ArgumentHelp("Create symlinks from app Resources to generated SBOM files"))
    var linkResource: Bool = false

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runSBOMCreate(with: out)
        }
    }

    func runSBOMCreate(with out: MessageQueue) async throws {
        let startTime = Date.now
        let fs = localFileSystem

        let generateIOS = ios || (!ios && !android)
        let generateAndroid = android || (!ios && !android)

        let packageJSON = try await parseSwiftPackage(with: out, at: project)
        let packageName = packageJSON.name

        let moduleNames = packageJSON.targets.compactMap(\.a).filter({ $0.type == "regular" }).filter({ $0.pluginUsages != nil }).map(\.name)
        guard let appModuleName = moduleNames.first else {
            throw error("No Skip module targets found in package \(packageName)")
        }

        let projectURL = URL(fileURLWithPath: self.project).standardized
        let resolvedProjectPath = projectURL.path

        let outputDir = self.dir ?? "."
        let outputDirAbsolute = try AbsolutePath(validating: outputDir, relativeTo: fs.currentWorkingDirectory!)
        try fs.createDirectory(outputDirAbsolute, recursive: true)

        let generatedFiles = try await generateSBOMFiles(
            generateIOS: generateIOS,
            generateAndroid: generateAndroid,
            projectPath: resolvedProjectPath,
            packageName: packageName,
            packageJSON: packageJSON,
            outputDirAbsolute: outputDirAbsolute,
            out: out
        )

        // Create resource symlinks if requested
        if linkResource {
            let resourcesFolder = projectURL.appendingPathComponent("Sources/\(appModuleName)/Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resourcesFolder, withIntermediateDirectories: true)

            for fileURL in generatedFiles {
                let linkPath = resourcesFolder.appendingPathComponent(fileURL.lastPathComponent).path
                try? FileManager.default.removeItem(atPath: linkPath)
                // Create a relative symlink from the Resources folder to the SBOM file
                let relativePath = relativePath(from: resourcesFolder.path, to: fileURL.path)
                try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: relativePath)
                await out.write(status: .pass, "Linked \(fileURL.lastPathComponent) -> \(relativePath)")
            }
        }

        await out.write(status: .pass, "Skip SBOM create \(packageName) (\(startTime.timingSecondsSinceNow))")
    }
}

// MARK: - Validate Subcommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct SBOMValidateCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate existing SBOM files against the current project state",
        usage: """
# validate SBOMs in current directory
skip sbom validate

# validate SBOMs in a specific directory
skip sbom validate -d ./output
""",
        discussion: """
Reads the existing SBOM files (sbom-darwin-ios.spdx.json and/or sbom-linux-android.spdx.json) \
and verifies that their dependency lists match the current project state. Reports any packages \
that have been added, removed, or changed version.
""",
        shouldDisplay: sbomCommandEnabled)

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Directory containing SBOM files to validate", valueName: "directory"))
    var dir: String?

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runSBOMValidate(with: out)
        }
    }

    func runSBOMValidate(with out: MessageQueue) async throws {
        let startTime = Date.now
        let fs = localFileSystem

        let packageJSON = try await parseSwiftPackage(with: out, at: project)
        let packageName = packageJSON.name

        let sbomDir = self.dir ?? "."
        let sbomDirAbsolute = try AbsolutePath(validating: sbomDir, relativeTo: fs.currentWorkingDirectory!)

        let projectURL = URL(fileURLWithPath: self.project).standardized
        let resolvedProjectPath = projectURL.path

        var hasErrors = false

        // Validate iOS SBOM
        let iosFile = sbomDirAbsolute.appending(component: SBOMGenerator.iosFilename)
        if fs.isFile(iosFile) {
            let valid = try await validateIOSSBOM(
                existingFile: iosFile,
                projectPath: resolvedProjectPath,
                packageName: packageName,
                packageJSON: packageJSON,
                out: out
            )
            if !valid { hasErrors = true }
        } else {
            await out.write(status: .warn, "iOS SBOM not found at \(iosFile.pathString)")
        }

        // Validate Android SBOM
        let androidFile = sbomDirAbsolute.appending(component: SBOMGenerator.androidFilename)
        if fs.isFile(androidFile) {
            let valid = try await validateAndroidSBOM(
                existingFile: androidFile,
                projectPath: resolvedProjectPath,
                packageName: packageName,
                out: out
            )
            if !valid { hasErrors = true }
        } else {
            await out.write(status: .warn, "Android SBOM not found at \(androidFile.pathString)")
        }

        if hasErrors {
            throw error("SBOM validation failed for \(packageName)")
        }
        await out.write(status: .pass, "Skip SBOM validate \(packageName) (\(startTime.timingSecondsSinceNow))")
    }

    func validateIOSSBOM(existingFile: AbsolutePath, projectPath: String, packageName: String, packageJSON: PackageManifest, out: MessageQueue) async throws -> Bool {
        let existingData = try Data(contentsOf: existingFile.asURL)
        guard let existingDoc = try JSONSerialization.jsonObject(with: existingData) as? [String: Any],
              let existingPackages = existingDoc["packages"] as? [[String: Any]] else {
            await out.write(status: .fail, "iOS SBOM: invalid SPDX document format")
            return false
        }

        let freshDoc = try SBOMGenerator.generateIOSSBOM(projectPath: projectPath, packageName: packageName, packageJSON: packageJSON)
        guard let freshPackages = freshDoc["packages"] as? [[String: Any]] else {
            await out.write(status: .fail, "iOS SBOM: could not generate fresh SBOM for comparison")
            return false
        }

        return await validatePackageLists(
            platform: "iOS",
            existingPackages: existingPackages,
            freshPackages: freshPackages,
            out: out
        )
    }

    func validateAndroidSBOM(existingFile: AbsolutePath, projectPath: String, packageName: String, out: MessageQueue) async throws -> Bool {
        let existingData = try Data(contentsOf: existingFile.asURL)
        guard let existingDoc = try JSONSerialization.jsonObject(with: existingData) as? [String: Any],
              let existingPackages = existingDoc["packages"] as? [[String: Any]] else {
            await out.write(status: .fail, "Android SBOM: invalid SPDX document format")
            return false
        }

        // Generate a fresh SBOM to a temp file via the spdx-gradle-plugin and compare
        let fs = localFileSystem
        let tempFile = try AbsolutePath(validating: NSTemporaryDirectory()).appending(component: "skip-sbom-validate-\(UUID().uuidString.prefix(8)).spdx.json")
        defer { try? fs.removeFileTree(tempFile) }

        try await SBOMGenerator.generateAndroidSBOM(projectPath: projectPath, packageName: packageName, outputFile: tempFile, command: self, out: out)

        let freshData = try Data(contentsOf: tempFile.asURL)
        guard let freshDoc = try JSONSerialization.jsonObject(with: freshData) as? [String: Any],
              let freshPackages = freshDoc["packages"] as? [[String: Any]] else {
            await out.write(status: .fail, "Android SBOM: could not generate fresh SBOM for comparison")
            return false
        }

        return await validatePackageLists(
            platform: "Android",
            existingPackages: existingPackages,
            freshPackages: freshPackages,
            out: out
        )
    }

    func validatePackageLists(platform: String, existingPackages: [[String: Any]], freshPackages: [[String: Any]], out: MessageQueue) async -> Bool {
        // Build maps of name -> version for comparison, excluding the root/app package.
        // For iOS SBOMs: root has primaryPackagePurpose == "APPLICATION".
        // For Android SBOMs (spdx-gradle-plugin): root is the app module with a simple name like "app".
        // Dependencies have names containing ":" (e.g., "org.jetbrains.kotlin:kotlin-stdlib")
        // or primaryPackagePurpose == "LIBRARY".
        func packageMap(_ packages: [[String: Any]]) -> [String: String] {
            var map: [String: String] = [:]
            for pkg in packages {
                guard let name = pkg["name"] as? String,
                      let version = pkg["versionInfo"] as? String else { continue }
                let purpose = pkg["primaryPackagePurpose"] as? String
                if purpose == "APPLICATION" { continue }
                // Skip the DOCUMENT entry and root project entries that don't look like dependencies
                if pkg["SPDXID"] as? String == "SPDXRef-DOCUMENT" { continue }
                // For spdx-gradle-plugin output, the root app has a simple name without ":"
                // while all Maven dependencies have "group:artifact" format
                if purpose == nil && !name.contains(":") { continue }
                map[name] = version
            }
            return map
        }

        let existingMap = packageMap(existingPackages)
        let freshMap = packageMap(freshPackages)

        var valid = true

        // Check for added dependencies
        for (name, version) in freshMap where existingMap[name] == nil {
            await out.write(status: .fail, "\(platform) SBOM: missing dependency \(name) \(version)")
            valid = false
        }

        // Check for removed dependencies
        for (name, version) in existingMap where freshMap[name] == nil {
            await out.write(status: .fail, "\(platform) SBOM: stale dependency \(name) \(version) (no longer present)")
            valid = false
        }

        // Check for version changes
        for (name, freshVersion) in freshMap {
            if let existingVersion = existingMap[name], existingVersion != freshVersion {
                await out.write(status: .fail, "\(platform) SBOM: version mismatch for \(name): SBOM has \(existingVersion), project has \(freshVersion)")
                valid = false
            }
        }

        if valid {
            await out.write(status: .pass, "\(platform) SBOM validated: \(existingMap.count) dependencies match")
        }

        return valid
    }
}

// MARK: - Verify Subcommand

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct SBOMVerifyCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify SBOM dependency licenses against a policy",
        usage: """
# allow only Apache-2.0 and MIT licenses
skip sbom verify --allow Apache-2.0 --allow MIT

# deny GPL licenses
skip sbom verify --deny GPL-3.0-only --deny GPL-2.0-only

# allow all FSF-compatible free/open-source licenses
skip sbom verify --free

# verify only Android licenses using the concluded field
skip sbom verify --free --android --concluded

# allow FLOSS but deny AGPL, and list specific NOASSERTION packages
skip sbom verify --free --deny AGPL-3.0-only --noassertion SPDXRef-gnrtd5 --noassertion SPDXRef-gnrtd12
""",
        discussion: """
Verify that all dependency licenses in the SBOM files conform to a specified policy. \
Use --allow to specify permitted SPDX license identifiers, or --deny to specify forbidden ones. \
The --free flag permits a curated set of licenses recognized as free/open-source by the FSF. \
By default, the licenseDeclared field is checked; use --concluded to check licenseConcluded instead.
""",
        shouldDisplay: sbomCommandEnabled)

    @Option(name: [.customShort("d"), .long], help: ArgumentHelp("Directory containing SBOM files", valueName: "directory"))
    var dir: String?

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Project folder", valueName: "dir"))
    var project: String = "."

    @Option(parsing: .upToNextOption, help: ArgumentHelp("SPDX identifiers for allowed licenses", valueName: "SPDX-ID"))
    var allow: [String] = []

    @Option(parsing: .upToNextOption, help: ArgumentHelp("SPDX identifiers for denied licenses", valueName: "SPDX-ID"))
    var deny: [String] = []

    @Flag(help: ArgumentHelp("Allow all FSF-recognized free/open-source licenses"))
    var free: Bool = false

    @Flag(help: ArgumentHelp("Verify iOS SBOM only"))
    var ios: Bool = false

    @Flag(help: ArgumentHelp("Verify Android SBOM only"))
    var android: Bool = false

    @Flag(help: ArgumentHelp("Check licenseDeclared field (default)"))
    var declared: Bool = false

    @Flag(help: ArgumentHelp("Check licenseConcluded field instead of licenseDeclared"))
    var concluded: Bool = false

    @Flag(name: .long, help: ArgumentHelp("Allow packages with NOASSERTION license (default)"))
    var allowNoassertion: Bool = false

    @Flag(name: .long, help: ArgumentHelp("Deny packages with NOASSERTION license"))
    var denyNoassertion: Bool = false

    @Option(parsing: .upToNextOption, help: ArgumentHelp("SPDX IDs of specific packages permitted to have NOASSERTION license (implies --deny-noassertion for unlisted packages)", valueName: "SPDXID"))
    var noassertion: [String] = []

    func performCommand(with out: MessageQueue) async {
        await withLogStream(with: out) {
            try await runSBOMVerify(with: out)
        }
    }

    func runSBOMVerify(with out: MessageQueue) async throws {
        let startTime = Date.now
        let fs = localFileSystem

        // Build the license policy
        let policy = try buildPolicy()

        let checkIOS = ios || (!ios && !android)
        let checkAndroid = android || (!ios && !android)

        // Determine the SBOM directory and whether files exist
        let sbomDirAbsolute: AbsolutePath
        var tempDir: AbsolutePath? = nil

        if let dir = self.dir {
            sbomDirAbsolute = try AbsolutePath(validating: dir, relativeTo: fs.currentWorkingDirectory!)
        } else {
            // Check current directory first
            let cwd = fs.currentWorkingDirectory!
            let iosExists = !checkIOS || fs.isFile(cwd.appending(component: SBOMGenerator.iosFilename))
            let androidExists = !checkAndroid || fs.isFile(cwd.appending(component: SBOMGenerator.androidFilename))

            if iosExists && androidExists {
                sbomDirAbsolute = cwd
            } else {
                // No pre-existing SBOM files found; generate them to a temp directory
                await out.write(status: .pass, "No SBOM files found, generating for verification")

                let projectURL = URL(fileURLWithPath: self.project).standardized
                let resolvedProjectPath = projectURL.path

                let packageJSON = try await parseSwiftPackage(with: out, at: self.project)

                let tmp = try AbsolutePath(validating: NSTemporaryDirectory()).appending(component: "skip-sbom-verify-\(UUID().uuidString.prefix(8))")
                try fs.createDirectory(tmp, recursive: true)
                tempDir = tmp

                try await SBOMGenerator.generateSBOMFiles(
                    generateIOS: checkIOS,
                    generateAndroid: checkAndroid,
                    projectPath: resolvedProjectPath,
                    packageName: packageJSON.name,
                    packageJSON: packageJSON,
                    outputDirAbsolute: tmp,
                    command: self,
                    out: out
                )

                sbomDirAbsolute = tmp
            }
        }

        defer { if let tempDir = tempDir { try? fs.removeFileTree(tempDir) } }

        var totalChecked = 0
        var totalViolations = 0

        if checkIOS {
            let iosFile = sbomDirAbsolute.appending(component: SBOMGenerator.iosFilename)
            if fs.isFile(iosFile) {
                let (checked, violations) = try await verifyPlatform(file: iosFile, platform: "iOS", policy: policy, out: out)
                totalChecked += checked
                totalViolations += violations
            } else {
                await out.write(status: .warn, "iOS SBOM not found at \(iosFile.pathString)")
            }
        }

        if checkAndroid {
            let androidFile = sbomDirAbsolute.appending(component: SBOMGenerator.androidFilename)
            if fs.isFile(androidFile) {
                let (checked, violations) = try await verifyPlatform(file: androidFile, platform: "Android", policy: policy, out: out)
                totalChecked += checked
                totalViolations += violations
            } else {
                await out.write(status: .warn, "Android SBOM not found at \(androidFile.pathString)")
            }
        }

        if totalViolations > 0 {
            throw error("\(totalViolations) license \(totalViolations == 1 ? "violation" : "violations") found in \(totalChecked) packages")
        }
        await out.write(status: .pass, "Skip SBOM verify: \(totalChecked) packages checked, no violations (\(startTime.timingSecondsSinceNow))")
    }

    // MARK: - Policy Construction

    typealias LicensePolicy = SBOMLicensePolicy
    typealias NoassertionMode = SBOMNoassertionMode

    func buildPolicy() throws -> LicensePolicy {
        // Determine the license field to check
        let licenseField: String
        if concluded {
            licenseField = "licenseConcluded"
        } else {
            licenseField = "licenseDeclared"
        }

        // Build the allowed set
        var allowedLicenses: Set<String>? = nil
        if !allow.isEmpty || free {
            var allowed = Set(allow)
            if free {
                allowed.formUnion(LicenseIdentification.flossLicenses)
            }
            allowedLicenses = allowed
        }

        // Build the denied set
        let deniedLicenses = Set(deny)

        // Determine NOASSERTION handling
        let noassertionMode: NoassertionMode
        if !noassertion.isEmpty {
            // Explicit list of permitted NOASSERTION packages implies deny for unlisted ones
            noassertionMode = .allowListed(Set(noassertion))
        } else if denyNoassertion {
            noassertionMode = .deny
        } else {
            noassertionMode = .allow
        }

        if allowedLicenses == nil && deniedLicenses.isEmpty {
            throw error("Specify at least one of --allow, --deny, or --free to define a license policy")
        }

        return LicensePolicy(
            allowedLicenses: allowedLicenses,
            deniedLicenses: deniedLicenses,
            licenseField: licenseField,
            noassertionMode: noassertionMode
        )
    }

    // MARK: - Verification

    func verifyPlatform(file: AbsolutePath, platform: String, policy: LicensePolicy, out: MessageQueue) async throws -> (checked: Int, violations: Int) {
        try await SBOMGenerator.verifySBOMPlatform(file: file, platform: platform, policy: policy, out: out)
    }
}

// MARK: - Shared SBOM Generation Logic

/// Shared SBOM generation functions used by both `skip sbom create` and `skip export --sbom`.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
enum SBOMGenerator {
    static let iosFilename = "sbom-darwin-ios.spdx.json"
    static let androidFilename = "sbom-linux-android.spdx.json"

    // MARK: - iOS SBOM Generation

    static func generateIOSSBOM(projectPath: String, packageName: String, packageJSON: PackageManifest) throws -> [String: Any] {
        // Find Package.resolved - check workspace first, then project root
        let resolvedPaths = [
            projectPath + "/Package.resolved",
            projectPath + "/Project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        ]

        var resolvedData: Data?
        var resolvedFilePath: String?
        for path in resolvedPaths {
            if let data = FileManager.default.contents(atPath: path) {
                resolvedData = data
                resolvedFilePath = path
                break
            }
        }

        guard let data = resolvedData, let _ = resolvedFilePath else {
            throw SBOMError(message: "Could not find or generate Package.resolved in \(projectPath)")
        }

        let resolved = try JSONDecoder().decode(PackageResolved.self, from: data)

        let checkoutsDir = projectPath + "/.build/checkouts"

        var packages: [[String: Any]] = []
        var relationships: [[String: Any]] = []
        let documentNamespace = "https://skip.dev/spdx/\(packageName)/ios"
        let rootSPDXID = "SPDXRef-Package-\(spdxSafeID(packageName))"

        // Root package
        packages.append([
            "SPDXID": rootSPDXID,
            "name": packageName,
            "versionInfo": "source",
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": false,
            "supplier": "NOASSERTION",
            "primaryPackagePurpose": "APPLICATION"
        ])

        relationships.append([
            "spdxElementId": "SPDXRef-DOCUMENT",
            "relationshipType": "DESCRIBES",
            "relatedSpdxElement": rootSPDXID
        ])

        for pin in resolved.pins {
            let depSPDXID = "SPDXRef-Package-\(spdxSafeID(pin.identity))"

            var pkg: [String: Any] = [
                "SPDXID": depSPDXID,
                "name": pin.identity,
                "versionInfo": pin.state.version,
                "downloadLocation": pin.location,
                "filesAnalyzed": false,
                "supplier": "NOASSERTION",
                "primaryPackagePurpose": "LIBRARY"
            ]

            pkg["externalRefs"] = [[
                "referenceCategory": "PACKAGE-MANAGER",
                "referenceType": "swiftpm",
                "referenceLocator": pin.location
            ]]

            let checkoutPath = checkoutsDir + "/" + pin.identity
            let license = LicenseIdentification.detectLicense(at: checkoutPath)
            if let license = license {
                pkg["licenseConcluded"] = license.spdxIdentifier
                pkg["licenseDeclared"] = license.spdxIdentifier
            } else {
                pkg["licenseConcluded"] = "NOASSERTION"
                pkg["licenseDeclared"] = "NOASSERTION"
            }
            pkg["copyrightText"] = "NOASSERTION"

            packages.append(pkg)

            relationships.append([
                "spdxElementId": rootSPDXID,
                "relationshipType": "DEPENDS_ON",
                "relatedSpdxElement": depSPDXID
            ])
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let now = dateFormatter.string(from: Date())

        return [
            "spdxVersion": "SPDX-2.3",
            "dataLicense": "CC0-1.0",
            "SPDXID": "SPDXRef-DOCUMENT",
            "name": "\(packageName)-ios",
            "documentNamespace": documentNamespace,
            "creationInfo": [
                "created": now,
                "creators": ["Tool: skip-sbom"],
                "licenseListVersion": "3.22"
            ] as [String: Any],
            "packages": packages,
            "relationships": relationships
        ]
    }

    // MARK: - Android SBOM Generation

    /// Generate the Android SBOM by running the spdx-gradle-plugin on the project's Android build.
    /// Uses a Gradle init script to inject the plugin into the existing Android project without
    /// modifying any project files.
    static func generateAndroidSBOM<C: StreamingCommand & OutputOptionsCommand>(projectPath: String, packageName: String, outputFile: AbsolutePath, command: C, out: MessageQueue) async throws {
        let fs = localFileSystem
        let env = ProcessInfo.processInfo.environmentWithDefaultToolPaths

        let androidFolder = projectPath + "/Android"
        let androidFolderAbsolute = try AbsolutePath(validating: androidFolder)

        guard fs.isFile(androidFolderAbsolute.appending(component: "settings.gradle.kts")) else {
            throw SBOMError(message: "Android project not found at \(androidFolder)")
        }

        // Write a Groovy init script that injects the spdx-sbom plugin into the :app module.
        // The script is idempotent — it skips projects that already have the plugin applied.
        let initScript = try AbsolutePath(validating: NSTemporaryDirectory()).appending(component: "skip-spdx-init-\(UUID().uuidString.prefix(8)).gradle")
        let initScriptContent = """
        initscript {
            repositories {
                mavenCentral()
                gradlePluginPortal()
            }
            dependencies {
                classpath 'org.spdx:spdx-gradle-plugin:+'
            }
        }

        allprojects {
            afterEvaluate { project ->
                if (project.plugins.hasPlugin('com.android.application') && !project.plugins.hasPlugin('org.spdx.sbom')) {
                    project.apply plugin: org.spdx.sbom.gradle.SpdxSbomPlugin
                    project.spdxSbom {
                        targets {
                            create("release") {
                                configurations.set(["releaseRuntimeClasspath"])
                            }
                        }
                    }
                }
            }
        }
        """
        try initScriptContent.write(toFile: initScript.pathString, atomically: true, encoding: .utf8)
        defer { try? fs.removeFileTree(initScript) }

        // Run spdxSbomForRelease on the real Android project with the init script
        try await command.run(with: out, "Generate Android SBOM", ["gradle", ":app:spdxSbomForRelease", "--init-script", initScript.pathString, "--project-dir", androidFolderAbsolute.pathString, "--console=plain"], environment: env)

        // The spdx plugin writes output to {app.buildDir}/spdx/release.spdx.json.
        // The Skip build plugin sets buildDir to {projectPath}/.build/Android/app
        let buildFolder = try AbsolutePath(validating: projectPath + "/.build")
        let spdxOutputDir = buildFolder.appending(components: ["Android", "app", "spdx"])

        // Search for the generated .spdx.json file
        guard fs.isDirectory(spdxOutputDir),
              let spdxFiles = try? fs.getDirectoryContents(spdxOutputDir),
              let spdxFileName = spdxFiles.first(where: { $0.hasSuffix(".spdx.json") }) else {
            throw SBOMError(message: "Gradle SPDX plugin did not produce output in \(spdxOutputDir.pathString)")
        }

        let spdxFile = spdxOutputDir.appending(component: spdxFileName)
        try? fs.removeFileTree(outputFile)
        try fs.copy(from: spdxFile, to: outputFile)
        await out.write(status: .pass, "Generated Android SBOM: \(outputFile.basename)")
    }

    // MARK: - High-Level Orchestration

    /// Generate SBOM files for the specified platforms, writing them to the output directory.
    /// Returns the URLs of the generated files. Used by both `skip sbom create` and `skip export --sbom`.
    @discardableResult
    static func generateSBOMFiles<C: StreamingCommand & OutputOptionsCommand>(generateIOS: Bool, generateAndroid: Bool, projectPath: String, packageName: String, packageJSON: PackageManifest, outputDirAbsolute: AbsolutePath, command: C, out: MessageQueue) async throws -> [URL] {
        let fs = localFileSystem
        try fs.createDirectory(outputDirAbsolute, recursive: true)
        var generatedFiles: [URL] = []

        if generateIOS {
            // Ensure SwiftPM dependencies are resolved so Package.resolved and .build/checkouts exist
            let resolvedPaths = [
                projectPath + "/Package.resolved",
                projectPath + "/Project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
            ]
            if !resolvedPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
                try await command.run(with: out, "Resolve Swift package dependencies", ["swift", "package", "resolve", "--package-path", projectPath])
            }

            let iosFile = outputDirAbsolute.appending(component: iosFilename)
            await command.outputOptions.monitor(with: out, "Generate iOS SBOM") { _ in
                let sbom = try generateIOSSBOM(projectPath: projectPath, packageName: packageName, packageJSON: packageJSON)
                let data = try JSONSerialization.data(withJSONObject: sbom, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                try data.write(to: iosFile.asURL)
                generatedFiles.append(iosFile.asURL)
                return try iosFile.asURL.fileSizeString
            }
        }

        if generateAndroid {
            let androidFile = outputDirAbsolute.appending(component: androidFilename)
            try await generateAndroidSBOM(projectPath: projectPath, packageName: packageName, outputFile: androidFile, command: command, out: out)
            generatedFiles.append(androidFile.asURL)
        }

        return generatedFiles
    }

    // MARK: - SBOM License Verification

    /// Verify SBOM licenses against a FLOSS policy, generating temporary SBOMs if needed.
    /// Returns the number of violations found (0 = all pass).
    @discardableResult
    static func verifyFLOSSLicenses<C: StreamingCommand & OutputOptionsCommand>(projectPath: String, packageName: String, packageJSON: PackageManifest, command: C, out: MessageQueue) async throws -> Int {
        let fs = localFileSystem

        // Generate SBOMs to a temp directory
        let tempDir = try AbsolutePath(validating: NSTemporaryDirectory()).appending(component: "skip-sbom-verify-\(UUID().uuidString.prefix(8))")
        try fs.createDirectory(tempDir, recursive: true)
        defer { try? fs.removeFileTree(tempDir) }

        try await generateSBOMFiles(
            generateIOS: true,
            generateAndroid: true,
            projectPath: projectPath,
            packageName: packageName,
            packageJSON: packageJSON,
            outputDirAbsolute: tempDir,
            command: command,
            out: out
        )

        // Verify both platforms with FLOSS policy
        var totalChecked = 0
        var totalViolations = 0

        let policy = SBOMLicensePolicy(
            allowedLicenses: LicenseIdentification.flossLicenses,
            deniedLicenses: [],
            licenseField: "licenseDeclared",
            noassertionMode: .allow
        )

        for (filename, platform) in [(iosFilename, "iOS"), (androidFilename, "Android")] {
            let file = tempDir.appending(component: filename)
            guard fs.isFile(file) else { continue }
            let (checked, violations) = try await verifySBOMPlatform(file: file, platform: platform, policy: policy, out: out)
            totalChecked += checked
            totalViolations += violations
        }

        if totalViolations > 0 {
            await out.write(status: .fail, "SBOM verify: \(totalViolations) license \(totalViolations == 1 ? "violation" : "violations") in \(totalChecked) packages")
        } else if totalChecked > 0 {
            await out.write(status: .pass, "SBOM verify: \(totalChecked) packages checked, all FLOSS-licensed")
        }

        return totalViolations
    }

    /// Verify the licenses in a single SPDX SBOM file against a policy.
    static func verifySBOMPlatform(file: AbsolutePath, platform: String, policy: SBOMLicensePolicy, out: MessageQueue) async throws -> (checked: Int, violations: Int) {
        let data = try Data(contentsOf: file.asURL)
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = doc["packages"] as? [[String: Any]] else {
            await out.write(status: .fail, "\(platform) SBOM: invalid SPDX document format")
            return (0, 1)
        }

        let licenseRefLookup = LicenseIdentification.buildLicenseRefLookup(from: doc)
        let licenseRefNames = LicenseIdentification.buildLicenseRefNames(from: doc)

        func displayLicense(_ license: String) -> String {
            guard license.contains("LicenseRef-") else { return license }
            var result = license
            for (ref, name) in licenseRefNames {
                if result.contains(ref) {
                    result = result.replacingOccurrences(of: ref, with: "\(name) (\(ref))")
                }
            }
            return result
        }

        var checked = 0
        var violations = 0

        for pkg in packages {
            guard let name = pkg["name"] as? String,
                  let spdxID = pkg["SPDXID"] as? String else { continue }

            let purpose = pkg["primaryPackagePurpose"] as? String
            if purpose == "APPLICATION" { continue }
            if spdxID == "SPDXRef-DOCUMENT" { continue }
            if purpose == nil && !name.contains(":") { continue }

            let version = pkg["versionInfo"] as? String ?? "?"
            var license = pkg[policy.licenseField] as? String ?? "NOASSERTION"

            if license.contains("LicenseRef-") {
                for (ref, resolved) in licenseRefLookup {
                    license = license.replacingOccurrences(of: ref, with: resolved)
                }
            }

            checked += 1

            if license == "NOASSERTION" {
                switch policy.noassertionMode {
                case .allow:
                    await out.write(status: .pass, "\(platform): \(name) \(version) — NOASSERTION (allowed)")
                case .deny:
                    await out.write(status: .fail, "\(platform): \(name) \(version) — NOASSERTION [\(spdxID)]")
                    violations += 1
                case .allowListed(let permitted):
                    if permitted.contains(spdxID) {
                        await out.write(status: .pass, "\(platform): \(name) \(version) — NOASSERTION (permitted [\(spdxID)])")
                    } else {
                        await out.write(status: .fail, "\(platform): \(name) \(version) — NOASSERTION (not in permitted list) [\(spdxID)]")
                        violations += 1
                    }
                }
                continue
            }

            let licenseComponents = LicenseIdentification.parseSPDXExpression(license)

            var denied = false
            for component in licenseComponents {
                if policy.deniedLicenses.contains(component) {
                    let detail = licenseComponents.count > 1 ? " (in \(displayLicense(license)))" : ""
                    await out.write(status: .fail, "\(platform): \(name) \(version) — \(displayLicense(component))\(detail) (denied)")
                    violations += 1
                    denied = true
                    break
                }
            }
            if denied { continue }

            if let allowed = policy.allowedLicenses {
                let disallowed = licenseComponents.filter { !allowed.contains($0) }
                if !disallowed.isEmpty {
                    let label = disallowed.count == 1 ? displayLicense(disallowed[0]) : displayLicense(license)
                    await out.write(status: .fail, "\(platform): \(name) \(version) — \(label) (not allowed)")
                    violations += 1
                    continue
                }
            }

            await out.write(status: .pass, "\(platform): \(name) \(version) — \(displayLicense(license))")
        }

        let summary = violations == 0 ? "all pass" : "\(violations) \(violations == 1 ? "violation" : "violations")"
        await out.write(status: violations == 0 ? .pass : .fail, "\(platform) SBOM: \(checked) packages verified (\(summary))")

        return (checked, violations)
    }

    // MARK: - Helpers

    static func spdxSafeID(_ input: String) -> String {
        input.map { c in
            if c.isLetter || c.isNumber || c == "." || c == "-" {
                return String(c)
            } else {
                return "-"
            }
        }.joined()
    }
}

/// Compute a relative path from a directory to a target file path.
/// Both paths should be absolute. The result is suitable for use as a symlink destination.
private func relativePath(from fromDir: String, to toPath: String) -> String {
    let fromComponents = URL(fileURLWithPath: fromDir).standardized.pathComponents
    let toComponents = URL(fileURLWithPath: toPath).standardized.pathComponents

    // Find the common prefix length
    var commonLength = 0
    while commonLength < fromComponents.count && commonLength < toComponents.count
            && fromComponents[commonLength] == toComponents[commonLength] {
        commonLength += 1
    }

    // Number of ".." needed to go up from fromDir to the common ancestor
    let ups = fromComponents.count - commonLength
    var parts = Array(repeating: "..", count: ups)
    // Append the remaining path components from toPath
    parts.append(contentsOf: toComponents[commonLength...])
    return parts.joined(separator: "/")
}

/// Shared license policy for SBOM verification, used by both `skip sbom verify` and `skip verify --sbom`.
struct SBOMLicensePolicy {
    let allowedLicenses: Set<String>?  // nil means no allowlist (all allowed unless denied)
    let deniedLicenses: Set<String>
    let licenseField: String           // "licenseDeclared" or "licenseConcluded"
    let noassertionMode: SBOMNoassertionMode
}

enum SBOMNoassertionMode {
    case allow
    case deny
    case allowListed(Set<String>)
}

struct SBOMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Convenience for SBOMCreateCommand to call shared code

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
extension SBOMCreateCommand {
    func generateSBOMFiles(generateIOS: Bool, generateAndroid: Bool, projectPath: String, packageName: String, packageJSON: PackageManifest, outputDirAbsolute: AbsolutePath, out: MessageQueue) async throws -> [URL] {
        try await SBOMGenerator.generateSBOMFiles(
            generateIOS: generateIOS,
            generateAndroid: generateAndroid,
            projectPath: projectPath,
            packageName: packageName,
            packageJSON: packageJSON,
            outputDirAbsolute: outputDirAbsolute,
            command: self,
            out: out
        )
    }
}
