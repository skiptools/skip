import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic

/// The `skip plugin` command will generate the Skip plugin code and output the path to the plugin.
/// It is means to be run from an app's settings.gradle.kts to ensure that the plugin is always available.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct PluginCommand: MessageCommand, ToolOptionsCommand {
    static var configuration = CommandConfiguration(
        commandName: "plugin",
        abstract: "Set up the Skip gradle plugin",
        shouldDisplay: false)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the Swift project before returning the plugin"))
    var prebuild: Bool = true

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @Option(help: ArgumentHelp("Swift package path", valueName: "package-path"))
    var packagePath: String?

    @Option(help: ArgumentHelp("Plugin output path reference", valueName: "plugin-reference"))
    var pluginRef: String?

    @Option(help: ArgumentHelp("Path to the Swift SDK for prebuild", valueName: "sdk-path"))
    var sdkPath: String?

    @Option(help: ArgumentHelp("Name of the Swift SDK for prebuild", valueName: "sdk-name"))
    var sdkName = "iphoneos"

    @Option(help: ArgumentHelp("Name of the build triple for prebuild", valueName: "triple"))
    var buildTriple = "arm64-apple-ios"

    struct PluginOutput : StringMessageEncodable {
        let line: String
        func message(term: Term) -> String? {
            //line
            term.cyan(line)
        }
    }

    func performCommand(with out: MessageQueue) async throws {
        let env = ProcessInfo.processInfo.environment
        let builtProductsDir = env["BUILT_PRODUCTS_DIR"]

        let isXcodeBuild = builtProductsDir != nil
        if !isXcodeBuild && self.prebuild == true {
            // when building from a non-Xcode environment, we need to manually perform a pre-build of the project
            var sdkPath = self.sdkPath
            if sdkPath == nil {
                // auto-discover the sdk path, like
                // /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS18.4.sdk
                sdkPath = try await launchTool("xcrun", arguments: ["--sdk", self.sdkName, "--show-sdk-path"]).readOutput().stdout
            }

            var prebuildCommand = ["swift", "build", "--triple", self.buildTriple]
            if let sdkPath = sdkPath {
                prebuildCommand += ["--sdk", sdkPath]
            }
            if let packagePath = packagePath {
                prebuildCommand += ["--package-path", packagePath]
            }

            try outputOptions.writeOutput(PluginOutput(line: "running pre-build command: \(prebuildCommand.joined(separator: " "))"), error: false)
            let buildOutput = try await launchTool("xcrun", arguments: prebuildCommand)

            for try await element in buildOutput {
                try outputOptions.writeOutput(PluginOutput(line: element.line), error: element.err)
            }
        }

        /// Figure out where to save the plugin itself; from an Xcode build, it will go somewhere like:
        /// `/Users/marc/Library/Developer/Xcode/DerivedData/Skip-Everything-aqywrhrzhkbvfseiqgxuufbdwdft/Build/Intermediates.noindex/HelloSkip.build/Debug-iphonesimulator/HelloSkip.build/DerivedSources/skip-gradle`
        /// and from the command-line, it will go in the project's `.build/Android/skip-gradle/`
        func installSkipGradlePlugin() throws -> AbsolutePath {
            let pluginOutputBasePath = env["DERIVED_SOURCES_DIR"] ?? packagePath?.appending("/.build/Android") ?? env["TMPDIR"] ?? NSTemporaryDirectory()

            /**
             ```
             .build/Android/skip-gradle
             ├── build.gradle.kts
             ├── settings.gradle.kts
             └── src
                 └── main
                     └── kotlin
                         └── SkipGradlePlugins.kt
             ```
             */
            let basePath = try AbsolutePath(validating: pluginOutputBasePath + "/skip-gradle")

            let settingsGradle = settingsGradleContent()
            let settingsGradlePath = try AbsolutePath(validating: "settings.gradle.kts", relativeTo: basePath)
            try writeChanges(to: settingsGradlePath, contents: settingsGradle)

            let buildGradle = buildGradleContent()
            let buildGradlePath = try AbsolutePath(validating: "build.gradle.kts", relativeTo: basePath)
            try writeChanges(to: buildGradlePath, contents: buildGradle)

            let pluginPath = try AbsolutePath(validating: "src/main/kotlin", relativeTo: basePath)
            try localFileSystem.createDirectory(pluginPath, recursive: true)

            let skipGradlePlugin = skipGradlePluginContent()
            let skipGradlePluginPath = try AbsolutePath(validating: "SkipGradlePlugins.kt", relativeTo: pluginPath)
            try writeChanges(to: skipGradlePluginPath, contents: skipGradlePlugin)

            return basePath
        }

        /*
         // local override of BUILT_PRODUCTS_DIR
         if (System.getenv("BUILT_PRODUCTS_DIR") == null) {
             //System.setProperty("BUILT_PRODUCTS_DIR", "${System.getProperty("user.home")}/Library/Developer/Xcode/DerivedData/MySkipProject-aqywrhrzhkbvfseiqgxuufbdwdft/Build/Products/Debug-iphonesimulator")
         }

         // the source for the plugin is linked as part of the SkipUnit transpilation
         val skipOutput = System.getenv("BUILT_PRODUCTS_DIR") ?: System.getProperty("BUILT_PRODUCTS_DIR")

         val outputExt = if (skipOutput != null) ".output" else "" // Xcode saves output in package-name.output; SPM has no suffix
         val skipOutputs: File = if (skipOutput != null) {
             // BUILT_PRODUCTS_DIR is set when building from Xcode, in which case we will use Xcode's DerivedData plugin output
             var outputs = file(skipOutput).resolve("../../../Build/Intermediates.noindex/BuildToolPluginIntermediates/") // Xcode 16.3+
             if (!outputs.isDirectory) {
                 outputs = file(skipOutput).resolve("../../../SourcePackages/plugins/") // Xcode 16.2-
             }
             outputs
         } else {
             exec {
                 // create transpiled Kotlin and generate Gradle projects from SwiftPM modules
                 commandLine("sh", "-c", "xcrun swift build --triple arm64-apple-ios --sdk $(xcrun --sdk iphoneos --show-sdk-path)")
                 workingDir = file("..")
             }
             // SPM output folder is a peer of the parent Package.swift
             rootDir.resolve("../.build/plugins/outputs/")
         }

         // load the Skip plugin (part of the skip-unit project), which handles configuring the Android project
         // because this path is a symlink, we need to use the canonical path or gradle will mis-interpret it as a different build source
         var pluginSource = skipOutputs.resolve("skip-unit${outputExt}/SkipUnit/destination/skipstone/buildSrc/").canonicalFile // SwiftPM 6+
         if (!pluginSource.isDirectory) {
             pluginSource = skipOutputs.resolve("skip-unit${outputExt}/SkipUnit/skipstone/buildSrc/").canonicalFile // SwiftPM 5.10-
         }

         print("pluginSource.path: ${pluginSource.path}\n")
         */

        let basePath = try installSkipGradlePlugin()
        // the command just outputs the path where the plugin was setup; this will be read by the settings.gradle.kts script so it can include the plugin with `includeBuild(pluginPath.readText())`
        if let pluginRef = pluginRef {
            let skipRefPath = try AbsolutePath(validating: pluginRef)
            try writeChanges(to: skipRefPath, contents: basePath.pathString, makeReadOnly: false)
        }
    }


    func writeChanges(to path: AbsolutePath, contents: String, makeReadOnly: Bool = true) throws {
        try localFileSystem.writeChanges(path: path, makeReadOnly: makeReadOnly, bytes: ByteString(encodingAsUTF8: contents))
    }

    /// Prints the given message to the standard error stream
    func printerr(_ msg: String) {
        try? FileHandle.standardError.write(contentsOf: Data((msg + "\n").utf8))
    }
}

private func settingsGradleContent() -> String {
"""
pluginManagement {
    repositories {
        mavenCentral()
        gradlePluginPortal()
        google()
    }
}

"""
}

private func buildGradleContent() -> String {
"""
plugins {
    `kotlin-dsl`
    `java-gradle-plugin`
}

repositories {
    google()
    mavenCentral()
}

gradlePlugin {
    plugins {
        create("skip-plugin") {
            id = "skip-plugin"
            implementationClass = "SkipSettingsPlugin"
        }
        create("skip-build-plugin") {
            id = "skip-build-plugin"
            implementationClass = "SkipBuildPlugin"
        }
    }
}

dependencies {
    compileOnly("com.android.tools.build:gradle:8.5.0")
}

"""
}

/// `SkipGradlePlugins.kt`
private func skipGradlePluginContent() -> String {
"""
// SPDX-License-Identifier: LGPL-3.0-only WITH LGPL-3.0-linking-exception
import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.initialization.Settings
import org.gradle.api.logging.Logger
import org.gradle.api.logging.Logging
import org.gradle.api.plugins.ExtensionAware
import org.gradle.api.provider.Property
import org.gradle.kotlin.dsl.apply
import org.gradle.kotlin.dsl.create
import org.gradle.kotlin.dsl.withGroovyBuilder
import org.gradle.process.ExecOperations
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileReader
import java.nio.charset.Charset
import java.util.*
import javax.inject.Inject

// the Skip.env configuration for a Skip app, with shared constants for Xcode and gradle
val skipEnvFilename = "Skip.env"

interface SkipBuildExtension {
    val appName: Property<String>
}

class SkipBuildPlugin @Inject constructor(private val os: ExecOperations) : Plugin<Project> {
    private var project: Project? = null

    override fun apply(project: Project) {
        val logger: Logger = project.logger
        fun info(message: String) = logger.info(message)

        // output in the standard Gradle warning format, which skip will parse and convert into an Xcode warning
        fun warn(message: String, path: String = "", line: Int = 0, column: Int = 0) = logger.warn("w: file://${path}:${line}:${column} ${message}")

        // output in the standard Gradle error format, which skip will parse and convert into an Xcode error
        fun error(message: String, path: String = "", line: Int = 0, column: Int = 0): Exception {
            logger.error("e: file://${path}:${line}:${column} ${message}")
            return RuntimeException(message)
        }

        fun findLine(startingWith: String, path: String): Int? {
            val file = java.io.File(path)
            if (!file.exists()) {
                throw IllegalArgumentException("File at path $path does not exist")
            }

            file.useLines { lines ->
                lines.forEachIndexed { index, line ->
                    if (line.trim().startsWith(startingWith)) {
                        return index + 1 // Line numbers start from 1
                    }
                }
            }

            return null
        }

        val buildFilePath = project.buildFile.absolutePath

        var validationFailures = 0

        // Try to add the compose compiler plugin if it does not exist in the project as part of the Kotlin 2 migration of existing projects
        // https://www.jetbrains.com/help/kotlin-multiplatform-dev/compose-compiler.html#migrating-a-compose-multiplatform-project
        // https://android-developers.googleblog.com/2024/04/jetpack-compose-compiler-moving-to-kotlin-repository.html
        if (!project.plugins.hasPlugin("org.jetbrains.kotlin.plugin.compose")) {
            // project.plugins.apply("org.jetbrains.kotlin.plugin.compose") // doesn't work: "Plugin with id 'org.jetbrains.kotlin.plugin.compose' not found"
            error("Manual upgrade required for Android/app/build.gradle.kts: add line to plugins block: alias(libs.plugins.kotlin.compose) Details: https://skip.tools/docs/kotlin2-migration/", path = buildFilePath, line = findLine(startingWith = "plugins {", path = buildFilePath) ?: 0)
            validationFailures += 1
        }

        // scan for android / composeOptions / kotlinCompilerExtensionVersion and raise an error
        val androidExtension = project.extensions.findByName("android") as? ExtensionAware
        if (androidExtension != null) {
            val composeOptions = androidExtension.extensions.findByName("composeOptions")
            if (composeOptions != null) {
                // always null…
            }
        }

        val kotlinCompilerExtensionVersionLine = findLine(startingWith = "kotlinCompilerExtensionVersion =", path = buildFilePath)
        if (kotlinCompilerExtensionVersionLine != null) {
            error("Manual upgrade required for Android/app/build.gradle.kts: remove the line kotlinCompilerExtensionVersion = … Details: https://skip.tools/docs/kotlin2-migration/", path = buildFilePath, line = kotlinCompilerExtensionVersionLine)
            validationFailures += 1
        }

        if (findLine(startingWith = "jvmTarget = ", path = buildFilePath) == null) {
            error("Manual upgrade required for Android/app/build.gradle.kts: android block should contain a kotlinOptions block with the line: jvmTarget = libs.versions.jvm.get().toString() Details: https://skip.tools/docs/kotlin2-migration/", path = buildFilePath)
            validationFailures += 1
        }

        if (validationFailures > 0) {
            throw error("Project validation errors (${validationFailures})")
        }

        this.project = project
        val baseDir = project.rootDir.resolve("..")
        val env = loadSkipEnv(baseDir.resolve(skipEnvFilename))

        with(project) {
            extensions.create("skip", SkipBuildExtension::class)
            // extensions: ext, libs, testLibs, versionCatalogs, kotlin, kotlinTestRegistry, base, defaultArtifacts, sourceSets, reporting, javaToolchains, java, android, androidComponents, buildOutputs, skip

            //val libsExtension = extensions.getByName("libs")
            val appName = env.skipEnv("PRODUCT_NAME")
            val packageName = env.skipEnv("ANDROID_PACKAGE_NAME")
            val appModule = packageName + ":" + appName
            val applicationId = env.skipEnv("PRODUCT_BUNDLE_IDENTIFIER").replace("-", "_")
            val activity = applicationId + "/" + packageName + ".MainActivity"
            dependencies.add("implementation", appModule)

            //val androidExtension = extensions.getByName("android") as com.android.build.gradle.BaseExtension // Unable to load class 'com.android.build.gradle.BaseExtension'
            // use a Groovy builder, which enables building up the DSL with access to the Android classes at runtime
            project.withGroovyBuilder {
                getProperty("android").withGroovyBuilder {
                    getProperty("defaultConfig").withGroovyBuilder {
                        setProperty("applicationId", applicationId)
                        setProperty("versionCode", env.skipEnv("CURRENT_PROJECT_VERSION").toInt())
                        setProperty("versionName", env.skipEnv("MARKETING_VERSION"))
                        getProperty("manifestPlaceholders").withGroovyBuilder {
                            // Configures the manifest placeholders for AndroidManifest.xml build-time replacement based on the keys in the Skip.env file
                            // Keys like PRODUCT_BUNDLE_IDENTIFIER and CURRENT_PROJECT_VERSION can be referenced directly in the manifest
                            env.forEach { (key, value) ->
                                setProperty(key.toString(), value)
                            }
                        }
                    }
                }
            }

            data class DeviceInfo(val serialNumber: String, val deviceType: String)

            /// Invoke `adb devices` and parse the output for the list of connected devices
            fun invokeADBDevices() : List<DeviceInfo> {
                val devicesOut = ByteArrayOutputStream()
                os.exec {
                    commandLine = listOf(
                        "adb".withExecutableExtension(),
                        "devices")
                    standardOutput = devicesOut
                }

                //warn("running adb devices: ${devicesOut}")

                val devicesOutString = devicesOut.toByteArray().toString(Charsets.UTF_8)
                val devices = mutableListOf<DeviceInfo>()

                val androidSerialsEnv = System.getenv("ANDROID_SERIAL")

                devicesOutString.lines().forEach { line ->
                    if (line.endsWith("\tdevice")) {
                        val parts = line.split("\t")
                        if (parts.size == 2) {
                            val serialNumber = parts[0]
                            val deviceType = parts[1]
                            // if we have set the ANDROID_SERIAL environment, only add the
                            // device to the list if it matches the serial number
                            if (androidSerialsEnv == null || androidSerialsEnv.isEmpty() || androidSerialsEnv == serialNumber) {
                                devices.add(DeviceInfo(serialNumber, deviceType))
                            }
                        }
                    }
                }

                return devices
            }

            @Suppress("DEPRECATION")
            task("checkDevices") {
                doFirst {
                    val devices = invokeADBDevices()
                    if (devices.size == 0) {
                        error("No connected Android devices or emulators were reported by `adb devices`. To launch the Skip app, start an emulator from the Android Studio Device Manager or use the ~/Library/Android/sdk/emulator/emulator command")
                    }
                }
            }

            // add the "launchDebug" and "launchRelease" commands
            listOf("Debug", "Release").forEach { buildType ->
                @Suppress("DEPRECATION")
                task("launch" + buildType) {
                    dependsOn("checkDevices") // check the devices before install to report when there are no devices
                    dependsOn("install" + buildType) // built-in install task

                    doLast {
                        val devices = invokeADBDevices()

                        if (devices.size > 1) {
                            val serials = devices.map({ it.serialNumber }).joinToString(", ")
                            warn("Multiple connected devices were reported by `adb devices`. Will attempt to launch on each device/emulator: ${serials}")
                        }

                        devices.forEach { device ->
                            //warn("launching app ${activity} on device: ${device.serialNumber}")
                            os.exec {
                                commandLine = listOf(
                                "adb".withExecutableExtension(),
                                "-s",
                                device.serialNumber,
                                "shell",
                                "am",
                                "start",
                                "-a",
                                "android.intent.action.MAIN",
                                "-c",
                                "android.intent.category.LAUNCHER",
                                "-n",
                                activity
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}


class SkipSettingsPlugin : Plugin<Settings> {
    override fun apply(settings: Settings) {
        val logger: Logger = Logging.getLogger(SkipSettingsPlugin::class.java)
        fun info(message: String) = logger.info(message)
        // output in the standard Gradle warning format, which skip will parse and convert into an Xcode warning
        fun warn(message: String) = logger.warn("w: file://:0:0 ${message}")
        // output in the standard Gradle error format, which skip will parse and convert into an Xcode error
        fun error(message: String) = logger.error("e: file://:0:0 ${message}")

        with(settings) {
            val baseDir = rootDir.resolve("..")
            val env = loadSkipEnv(baseDir.resolve(skipEnvFilename))

            // Use the shared ../.build/Android/ build folder as the gradle build output
            val buildDir = baseDir.resolve(".build")
            val buildOutput = buildDir.resolve("Android")

            gradle.projectsLoaded {
                rootProject.allprojects {
                    layout.buildDirectory.set(buildOutput.resolve(project.name))
                }
            }

            rootProject.name = env.skipEnv("ANDROID_PACKAGE_NAME")
            val swiftModuleName = env.skipEnv("PRODUCT_NAME")

            // the source for the plugin is linked as part of the SkipUnit transpilation
            val skipOutput = System.getenv("BUILT_PRODUCTS_DIR") ?: System.getProperty("BUILT_PRODUCTS_DIR")
            val skipOutputs: File = if (skipOutput != null) {
                // BUILT_PRODUCTS_DIR is set when building from Xcode, in which case we will use Xcode's DerivedData plugin output folder for the build project
                var outputs = File(skipOutput).resolve("../../../Build/Intermediates.noindex/BuildToolPluginIntermediates/") // Xcode 16.3+
                if (!outputs.exists()) {
                    outputs = File(skipOutput).resolve("../../../SourcePackages/plugins/") // Xcode 16.2-
                }
                outputs
            } else {
                // SPM output folder is a peer of the parent Package.swift in the .build folder
                buildDir.resolve("plugins/outputs/")
            }

            //warn("checking skipOutputs: ${skipOutputs}")
            if (!skipOutputs.exists()) {
                error("The expected plugin output folder did not exist at ${skipOutputs}. This may mean that the Skip project was not transpiled successfully, or that the skipstone transpiler plugin is not enabled for the project. Check the gradle log for details and see https://skip.tools/docs/faq/ for troubleshooting.")
            }

            // look in each of the output folders and return the first one for which the ModuleName/skipstone/ folder exists.
            // we used to use the SKIP_PROJECT_NAME project setting, but that requires that the Swift package app name was identical to the folder name in which the project resided, so this is more robust (at the cost of potentially having conflicting module names, if one should exist)
            // Note that we need to check for "destination" as well, as SwiftPM6 added it to the plugin output folder for command-line builds
            val projectBaseDir = skipOutputs.listFiles().firstOrNull { path ->
                //warn("checking skipOutputs child: ${path}")
                path.resolve(swiftModuleName).resolve("skipstone").exists()
                    || path.resolve(swiftModuleName).resolve("destination").resolve("skipstone").exists()
            }

            if (projectBaseDir == null) {
                error("Could not locate transpiled module for ${swiftModuleName} in ${skipOutputs}. This may mean that the Skip project was not transpiled successfully. Check the gradle log for details and see https://skip.tools/docs/faq/ for troubleshooting.")
            } else {
                var projectDir = projectBaseDir
                    .resolve(swiftModuleName)
                    .resolve("skipstone")
                if (!projectDir.exists()) {
                    // added for SwiftPM6 plugin output folder
                    projectDir = projectBaseDir
                        .resolve(swiftModuleName)
                        .resolve("destination")
                        .resolve("skipstone")
                }
                if (!projectDir.exists()) {
                    error("The folder at ${projectDir} does not exist. This may mean that the Skip project was not transpiled successfully, or the name of the project module is not unique in the packages that were created. Check the gradle log for details and see https://skip.tools/docs/faq/ for troubleshooting.")
                }

                // apply the settings directly to get the dependencies, which provides the "libs" versionCatalog
                apply(projectDir.resolve("settings.gradle.kts"))
                // add all the Skip dependant projects
                includeBuild(projectDir)
                // finally, include the local app scaffold
                include(":app")
            }
        }
    }
}

// Look up the expected property in the Skip.env file
private fun Properties.skipEnv(key: String) : String {
    val value = getProperty(key, System.getProperty("SKIP_${key}"))
    if (value == null) {
        throw GradleException("Required key ${key} is not set in top-level ${skipEnvFilename} file or system property SKIP_${key}")
    }
    return value
}

private fun String.withExecutableExtension() : String {
    if (org.gradle.internal.os.OperatingSystem.current().isWindows) {
        return this + ".exe"
    } else {
        return this
    }
}

// Parse the Skip.env key-value pairs, which is expected to be in the parent of the settings.gradle.kts
fun loadSkipEnv(from: File): Properties {
    if (!from.isFile) {
        throw GradleException("Missing expected ${from.name} configuration file in the root folder of the project: ${from}.")
    }

    val props = Properties()
    props.load(FileReader(from, Charset.forName("utf-8")))
    // the Skip.env file is an .xcconfig format, which can use "//" for comments
    // this is interpreted by the Java properties format as a key value pair, so just manually trim it out
    props.remove("//")
    return props
}

"""
}
