import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct LibInitCommand: MessageCommand, CreateOptionsCommand, ProjectCommand, ToolOptionsCommand, BuildOptionsCommand, StreamingCommand {
    static var configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize a new Skip library project",
        shouldDisplay: true)

    @OptionGroup(title: "Output Options")
    var outputOptions: OutputOptions

    @OptionGroup(title: "Create Options")
    var createOptions: CreateOptions

    @OptionGroup(title: "Tool Options")
    var toolOptions: ToolOptions

    @OptionGroup(title: "Build Options")
    var buildOptions: BuildOptions

    @Argument(help: ArgumentHelp("Project folder name"))
    var projectName: String

    @Argument(help: ArgumentHelp("The module name(s) to create"))
    var moduleNames: [String]

    @Option(help: ArgumentHelp("Embed the library as an app with the given bundle id"))
    var appid: String? = nil

    @Option(help: ArgumentHelp("Set the initial version to the given value"))
    var version: String? = nil

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the Android .apk file"))
    var apk: Bool = false

    @Flag(inversion: .prefixedNo, help: ArgumentHelp("Build the iOS .ipa file"))
    var ipa: Bool = false

    @Flag(help: ArgumentHelp("Open the resulting project in Xcode"))
    var openXcode: Bool = false

    //@Flag(help: ArgumentHelp("Open the resulting project in Android Studio"))
    //var openStudio: Bool = false

    /// Attempts to parse module names like "skiptools/skip-ui/SkipUI" into a full repo and path
    var modules: [PackageModule] {
        get throws {
            try self.moduleNames.map {
                try PackageModule(parse: $0)
            }
        }
    }

    var project: String {
        (self.createOptions.dir ?? ".")
    }

    func performCommand(with out: MessageQueue) async throws {
        await out.yield(MessageBlock(status: nil, "Initializing Skip library \(self.projectName)"))

        let dir = URL(fileURLWithPath: self.createOptions.dir ?? ".", isDirectory: true)

        let modules = try self.modules
        let (createdURL, _) = try await buildSkipProject(projectName: self.projectName, modules: modules, resourceFolder: createOptions.resourcePath, dir: dir, verify: buildOptions.verify, configuration: createOptions.configuration, build: buildOptions.build, test: buildOptions.test, returnHashes: false, showTree: self.createOptions.showTree, chain: createOptions.chain, gitRepo: createOptions.gitRepo, free: createOptions.free, zero: createOptions.zero, appid: self.appid, version: self.version, moduleTests: self.createOptions.moduleTests, validatePackage: self.createOptions.validatePackage, apk: apk, ipa: ipa, with: out)

        await out.yield(MessageBlock(status: .pass, "Created module \(modules.map(\.moduleName).joined(separator: ", ")) in \(createdURL.path)"))

        if openXcode {
            await run(with: out, "Opening Xcode project", ["open", createdURL.path])
        }

        // TODO: ensure the project was transpiled, find the settings.gradle.kts for the primary module, and open it
        //if openAndroid {
        //    await run(with: out, "Opening Gradle project", ["open", projectGradleSettings.path])
        //}
    }
}

extension ToolOptionsCommand {
    fileprivate func createXcodeProj(appModuleName: String, appMainSwiftFileName: String, Assets_xcassets_name: String, xcconfigFileName: String, primaryModuleAppTarget: String, primaryModuleAppMainPath: String, Assets_xcassets_path: String, Capabilities_entitlements_name: String, Capabilities_entitlements_path: String) -> String {
        let skipBuildAPKScript = """
        if [ "${SKIP_BUILD_APK}" != "YES" -o "${SKIP_ZERO}" != "" ]; then
          echo "note: Not building apk due to SKIP_BUILD_APK setting"
          exit 0
        fi

        PROJECT=$(basename ${PROJECT_DIR})
        PLUGIN=${BUILD_ROOT}/../../SourcePackages/artifacts/skip/skip/skip.artifactbundle/macos
        PATH=${BUILD_ROOT}/Debug:${PLUGIN}:${PATH}:${HOMEBREW_PREFIX:-/opt/homebrew}/bin
        ANDROID_HOME=${ANDROID_HOME:-${HOME}/Library/Android/sdk}
        SRCPKG=${BUILD_ROOT}/../../SourcePackages
        echo "note: Building APK for: ${PROJECT}"
        which skip
        mkdir -p Skip/build/artifacts/
        skip gradle --package "${PROJECT}" --module ${PROJECT_NAME} assemble${CONFIGURATION}
        cd Skip/build/
        ln -sfh ${SRCPKG}/plugins/*.output .
        cd artifacts/
        ln -f ${SRCPKG}/plugins/*.output/*/skipstone/*/.build/*/outputs/apk/*/*.apk .
        """
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let skipLaunchAPKScript = """
        if [ "${SKIP_LAUNCH_APK}" != "YES" -o "${SKIP_ZERO}" != "" ]; then
          echo "note: Not launching apk due to SKIP_LAUNCH_APK setting"
          exit 0
        fi

        PROJECT=$(basename ${PROJECT_DIR})
        PLUGIN=${BUILD_ROOT}/../../SourcePackages/artifacts/skip/skip/skip.artifactbundle/macos
        PATH=${BUILD_ROOT}/Debug:${PLUGIN}:${PATH}:${HOMEBREW_PREFIX:-/opt/homebrew}/bin
        ANDROID_HOME=${ANDROID_HOME:-${HOME}/Library/Android/sdk}

        echo "note: Running skip adb install"
        skip adb install -t -r -d -g Skip/build/artifacts/${PROJECT_NAME}-${CONFIGURATION}.apk
        echo "note: Running skip adb am start-activity"
        skip adb shell am start-activity -S -W -n ${PRODUCT_BUNDLE_IDENTIFIER}/${ANDROID_PACKAGE_NAME}.MainActivity

        """
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\"", with: "\\\"")



        return """
// !$*UTF8*$!
{
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 56;
    objects = {

/* Begin PBXBuildFile section */
        49231BAC2AC5BCEF00F98ADF /* \(appModuleName) in Frameworks */ = {isa = PBXBuildFile; productRef = 49231BAB2AC5BCEF00F98ADF /* \(appModuleName) */; };
        49231BAD2AC5BCEF00F98ADF /* \(appModuleName) in Embed Frameworks */ = {isa = PBXBuildFile; productRef = 49231BAB2AC5BCEF00F98ADF /* \(appModuleName) */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };
        499CD43B2AC5B799001AE8D8 /* \(appMainSwiftFileName) in Sources */ = {isa = PBXBuildFile; fileRef = 49F90C2B2A52156200F06D93 /* \(appMainSwiftFileName) */; };
        499CD4402AC5B799001AE8D8 /* \(Assets_xcassets_name) in Resources */ = {isa = PBXBuildFile; fileRef = 49F90C2F2A52156300F06D93 /* \(Assets_xcassets_name) */; };
/* End PBXBuildFile section */

/* Begin PBXCopyFilesBuildPhase section */
        499CD44A2AC5B9C6001AE8D8 /* Embed Frameworks */ = {
            isa = PBXCopyFilesBuildPhase;
            buildActionMask = 2147483647;
            dstPath = "";
            dstSubfolderSpec = 10;
            files = (
                49231BAD2AC5BCEF00F98ADF /* \(appModuleName) in Embed Frameworks */,
            );
            name = "Embed Frameworks";
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
        493609562A6B7EAE00C401E2 /* \(appModuleName) */ = {isa = PBXFileReference; lastKnownFileType = wrapper; name = \(appModuleName); path = .; sourceTree = "<group>"; };
        496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = \(xcconfigFileName); sourceTree = "<group>"; };
        4990AB3B2A91AFC5005777FD /* XCTest.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = XCTest.framework; path = Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework; sourceTree = DEVELOPER_DIR; };
        499CD4442AC5B799001AE8D8 /* \(primaryModuleAppTarget).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(primaryModuleAppTarget).app; sourceTree = BUILT_PRODUCTS_DIR; };
        49F90C2B2A52156200F06D93 /* \(appMainSwiftFileName) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = \(appMainSwiftFileName); path = \(primaryModuleAppMainPath); sourceTree = SOURCE_ROOT; };
        49F90C2F2A52156300F06D93 /* \(Assets_xcassets_name) */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; name = \(Assets_xcassets_name); path = \(Assets_xcassets_path); sourceTree = "<group>"; };
        49F90C312A52156300F06D93 /* \(Capabilities_entitlements_name) */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = \(Capabilities_entitlements_name); path = \(Capabilities_entitlements_path); sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
        499CD43C2AC5B799001AE8D8 /* Frameworks */ = {
            isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647;
            files = (
                49231BAC2AC5BCEF00F98ADF /* \(appModuleName) in Frameworks */,
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
        49429E532A61E02A00AA21A8 /* Frameworks */ = {
            isa = PBXGroup;
            children = (
                4990AB3B2A91AFC5005777FD /* XCTest.framework */,
            );
            name = Frameworks;
            sourceTree = "<group>";
        };
        49F90C1F2A52156200F06D93 = {
            isa = PBXGroup;
            children = (
                496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */,
                493609562A6B7EAE00C401E2 /* \(appModuleName) */,
                49F90C2A2A52156200F06D93 /* App */,
                49F90C292A52156200F06D93 /* Products */,
                49429E532A61E02A00AA21A8 /* Frameworks */,
            );
            sourceTree = "<group>";
        };
        49F90C292A52156200F06D93 /* Products */ = {
            isa = PBXGroup;
            children = (
                499CD4442AC5B799001AE8D8 /* \(primaryModuleAppTarget).app */,
            );
            name = Products;
            sourceTree = "<group>";
        };
        49F90C2A2A52156200F06D93 /* App */ = {
            isa = PBXGroup;
            children = (
                49F90C2B2A52156200F06D93 /* \(appMainSwiftFileName) */,
                49F90C2F2A52156300F06D93 /* \(Assets_xcassets_name) */,
                49F90C312A52156300F06D93 /* \(Capabilities_entitlements_name) */,
            );
            name = App;
            sourceTree = "<group>";
        };
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
        499CD4382AC5B799001AE8D8 /* \(primaryModuleAppTarget) */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = 499CD4412AC5B799001AE8D8 /* Build configuration list for PBXNativeTarget "\(primaryModuleAppTarget)" */;
            buildPhases = (
                499CD43A2AC5B799001AE8D8 /* Sources */,
                499CD43C2AC5B799001AE8D8 /* Frameworks */,
                499CD43E2AC5B799001AE8D8 /* Resources */,
                499CD4452AC5B869001AE8D8 /* Build Android APK */,
                499CD4462AC5B86B001AE8D8 /* Launch Android APK */,
                499CD44A2AC5B9C6001AE8D8 /* Embed Frameworks */,
            );
            buildRules = (
            );
            dependencies = (
            );
            name = \(primaryModuleAppTarget);
            packageProductDependencies = (
                49231BAB2AC5BCEF00F98ADF /* \(appModuleName) */,
            );
            productName = App;
            productReference = 499CD4442AC5B799001AE8D8 /* \(primaryModuleAppTarget).app */;
            productType = "com.apple.product-type.application";
        };
/* End PBXNativeTarget section */

/* Begin PBXProject section */
        49F90C202A52156200F06D93 /* Project object */ = {
            isa = PBXProject;
            attributes = {
                BuildIndependentTargetsInParallel = 1;
                LastSwiftUpdateCheck = 1430;
                LastUpgradeCheck = 1500;
            };
            buildConfigurationList = 49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(appModuleName)" */;
            compatibilityVersion = "Xcode 14.0";
            developmentRegion = en;
            hasScannedForEncodings = 0;
            knownRegions = (
                en,
                Base,
            );
            mainGroup = 49F90C1F2A52156200F06D93;
            packageReferences = (
            );
            productRefGroup = 49F90C292A52156200F06D93 /* Products */;
            projectDirPath = "";
            projectRoot = "";
            targets = (
                499CD4382AC5B799001AE8D8 /* \(primaryModuleAppTarget) */,
            );
        };
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
        499CD43E2AC5B799001AE8D8 /* Resources */ = {
            isa = PBXResourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
                499CD4402AC5B799001AE8D8 /* \(Assets_xcassets_name) in Resources */,
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXResourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
        499CD4452AC5B869001AE8D8 /* Build Android APK */ = {
            isa = PBXShellScriptBuildPhase;
            alwaysOutOfDate = 1;
            buildActionMask = 2147483647;
            files = (
            );
            inputFileListPaths = (
            );
            inputPaths = (
            );
            name = "Build Android APK";
            outputFileListPaths = (
            );
            outputPaths = (
            );
            runOnlyForDeploymentPostprocessing = 0;
            shellPath = "/bin/sh -e";
            shellScript = "\(skipBuildAPKScript)";
        };
        499CD4462AC5B86B001AE8D8 /* Launch Android APK */ = {
            isa = PBXShellScriptBuildPhase;
            alwaysOutOfDate = 1;
            buildActionMask = 2147483647;
            files = (
            );
            inputFileListPaths = (
            );
            inputPaths = (
            );
            name = "Launch Android APK";
            outputFileListPaths = (
            );
            outputPaths = (
            );
            runOnlyForDeploymentPostprocessing = 0;
            shellPath = "/bin/sh -e";
            shellScript = "\(skipLaunchAPKScript)";
        };
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
        499CD43A2AC5B799001AE8D8 /* Sources */ = {
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
                499CD43B2AC5B799001AE8D8 /* \(appMainSwiftFileName) in Sources */,
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
        491FCC8E2AD18D38002FB1E1 /* Skippy */ = {
            isa = XCBuildConfiguration;
            baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */;
            buildSettings = {
                ALWAYS_SEARCH_USER_PATHS = NO;
                ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                COPY_PHASE_STRIP = NO;
                DEBUG_INFORMATION_FORMAT = dwarf;
                ENABLE_BITCODE = NO;
                ENABLE_NS_ASSERTIONS = NO;
                ENABLE_STRICT_OBJC_MSGSEND = YES;
                ENABLE_USER_SCRIPT_SANDBOXING = NO;
                LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                MTL_ENABLE_DEBUG_INFO = NO;
                MTL_FAST_MATH = YES;
                SWIFT_COMPILATION_MODE = wholemodule;
            };
            name = Skippy;
        };
        491FCC8F2AD18D38002FB1E1 /* Skippy */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                ENABLE_PREVIEWS = YES;
                IPHONEOS_DEPLOYMENT_TARGET = 16.4;
                LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
                MACOSX_DEPLOYMENT_TARGET = 13.4;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SDKROOT = auto;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SWIFT_EMIT_LOC_STRINGS = YES;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            name = Skippy;
        };
        499CD4422AC5B799001AE8D8 /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                ENABLE_PREVIEWS = YES;
                IPHONEOS_DEPLOYMENT_TARGET = 16.4;
                LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
                MACOSX_DEPLOYMENT_TARGET = 13.4;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SDKROOT = auto;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SWIFT_EMIT_LOC_STRINGS = YES;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            name = Debug;
        };
        499CD4432AC5B799001AE8D8 /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                ENABLE_PREVIEWS = YES;
                IPHONEOS_DEPLOYMENT_TARGET = 16.4;
                LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
                MACOSX_DEPLOYMENT_TARGET = 13.4;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SDKROOT = auto;
                SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx";
                SWIFT_EMIT_LOC_STRINGS = YES;
                SWIFT_VERSION = 5.0;
                TARGETED_DEVICE_FAMILY = "1,2";
            };
            name = Release;
        };
        49F90C4B2A52156300F06D93 /* Debug */ = {
            isa = XCBuildConfiguration;
            baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */;
            buildSettings = {
                ALWAYS_SEARCH_USER_PATHS = NO;
                ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                COPY_PHASE_STRIP = NO;
                DEBUG_INFORMATION_FORMAT = dwarf;
                ENABLE_BITCODE = NO;
                ENABLE_STRICT_OBJC_MSGSEND = YES;
                ENABLE_TESTABILITY = YES;
                ENABLE_USER_SCRIPT_SANDBOXING = NO;
                LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
                MTL_FAST_MATH = YES;
                ONLY_ACTIVE_ARCH = YES;
                SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
                SWIFT_OPTIMIZATION_LEVEL = "-Onone";
            };
            name = Debug;
        };
        49F90C4C2A52156300F06D93 /* Release */ = {
            isa = XCBuildConfiguration;
            baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(xcconfigFileName) */;
            buildSettings = {
                ALWAYS_SEARCH_USER_PATHS = NO;
                ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                COPY_PHASE_STRIP = NO;
                DEBUG_INFORMATION_FORMAT = dwarf;
                ENABLE_BITCODE = NO;
                ENABLE_NS_ASSERTIONS = NO;
                ENABLE_STRICT_OBJC_MSGSEND = YES;
                ENABLE_USER_SCRIPT_SANDBOXING = NO;
                LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
                MTL_ENABLE_DEBUG_INFO = NO;
                MTL_FAST_MATH = YES;
                SWIFT_COMPILATION_MODE = wholemodule;
            };
            name = Release;
        };
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
        499CD4412AC5B799001AE8D8 /* Build configuration list for PBXNativeTarget "\(primaryModuleAppTarget)" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                499CD4422AC5B799001AE8D8 /* Debug */,
                499CD4432AC5B799001AE8D8 /* Release */,
                491FCC8F2AD18D38002FB1E1 /* Skippy */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
        49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(appModuleName)" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                49F90C4B2A52156300F06D93 /* Debug */,
                49F90C4C2A52156300F06D93 /* Release */,
                491FCC8E2AD18D38002FB1E1 /* Skippy */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
/* End XCConfigurationList section */

/* Begin XCSwiftPackageProductDependency section */
        49231BAB2AC5BCEF00F98ADF /* \(appModuleName) */ = {
            isa = XCSwiftPackageProductDependency;
            productName = \(appModuleName);
        };
/* End XCSwiftPackageProductDependency section */
    };
    rootObject = 49F90C202A52156200F06D93 /* Project object */;
}

"""
    }

    func buildSkipProject(projectName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, verify: Bool, configuration: String, build: Bool, test: Bool, returnHashes: Bool, messagePrefix: String? = nil, showTree: Bool, chain: Bool, gitRepo: Bool, free: Bool, zero skipZeroSupport: Bool, appid: String?, version: String?, moduleTests: Bool, validatePackage: Bool, packageResolved packageResolvedURL: URL? = nil, apk: Bool, ipa: Bool, with out: MessageQueue) async throws -> (projectURL: URL, artifacts: [URL: String?]) {
        let sourceHeader = free ? licenseLGPLHeader : ""
        let projectURL = try await initSkipLibrary(projectName: projectName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, verify: verify, chain: chain, gitRepo: gitRepo, free: free, zero: skipZeroSupport, app: appid != nil, moduleTests: moduleTests, validatePackage: validatePackage, packageResolved: packageResolvedURL, with: out)

        let projectPath = try projectURL.absolutePath
        let primaryModuleName = modules.first?.moduleName ?? "Module"

        let sourcesFolderName = "Sources"
        let buildFolderName = ".build"

        let re = messagePrefix ?? ""

        // the suffix for build artifacts
        // TODO: include version number from xcconfig
        // let cfgSuffix = "-" + (version ?? "0.0.1") + "-" + configuration
        let cfgSuffix = "-" + configuration

        let appModuleName = primaryModuleName
        let primaryModuleAppTarget = appModuleName + "App"
        let appModulePackage = KotlinTranslator.packageName(forModule: appModuleName)

        let xcodeProjectFolder = try projectURL.append(path: primaryModuleName + ".xcodeproj", create: appid != nil)

        if let appid = appid { // we have specified that an app should be created
            let primaryModuleAppSourcesPath = sourcesFolderName + "/" + primaryModuleAppTarget
            let appMainSwiftFileName = primaryModuleAppTarget + "Main.swift" // the main entry point to the app, as compiled by Xcode
            let primaryModuleAppMainPath = primaryModuleAppSourcesPath + "/" + appMainSwiftFileName
            let primaryModuleSources = sourcesFolderName + "/" + primaryModuleName

            // the Sources/MODULE_NAMEApp/ folder for iOS metadata
            //let appModule_Sources_Path = sourcesFolderName + "/" + primaryModuleAppTarget
            let appModule_Metadata_Path = primaryModuleSources + "/Skip"

            let Capabilities_entitlements_name = "Capabilities.entitlements"
            // TODO: let Capabilities_entitlements_name = "Entitlements.plist"
            let Capabilities_entitlements_path = appModule_Metadata_Path + "/" + Capabilities_entitlements_name

            let primaryModuleAppEntitlementsURL = projectURL.appending(path: Capabilities_entitlements_path)
            try FileManager.default.createDirectory(at: primaryModuleAppEntitlementsURL.deletingLastPathComponent(), withIntermediateDirectories: true)


            // Sources/PlaygroundApp/Entitlements.plist
            let appEntitlementsContents = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
            </dict>
            </plist>

            """

            try appEntitlementsContents.write(to: primaryModuleAppEntitlementsURL, atomically: true, encoding: .utf8)


            // create the top-level ModuleName.xcconfig which is the source or truth for the iOS and Android builds
            let configContents = """
            // The configuration file for your Skip App (https://skip.tools)

            // PRODUCT_NAME is the default title of the app
            PRODUCT_NAME = \(appModuleName)

            // PRODUCT_BUNDLE_IDENTIFIER is the unique id for both the iOS and Android app
            PRODUCT_BUNDLE_IDENTIFIER = \(appid)

            // The semantic version of the app
            MARKETING_VERSION = \(version ?? "0.0.1")

            // The build number specifying the internal app version
            CURRENT_PROJECT_VERSION = 1

            IPHONEOS_DEPLOYMENT_TARGET = 16.0
            MACOSX_DEPLOYMENT_TARGET = 13.0

            // On-device testing may need to override the bundle ID
            // PRODUCT_BUNDLE_IDENTIFIER[config=Debug][sdk=iphoneos*] = \(appid)

            // The package name for the Android entry point, referenced by the AndroidManifest.xml
            ANDROID_PACKAGE_NAME = \(appModulePackage)

            // Assemble the APK as part of the build process
            SKIP_BUILD_APK = YES

            // Building the target will lauch the app for iphone* targets
            SKIP_LAUNCH_APK[sdk=iphone*] = YES

            ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
            ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor

            GENERATE_INFOPLIST_FILE = YES
            // The user-visible name of the app (localizable)
            //INFOPLIST_KEY_CFBundleDisplayName = App Name
            //INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.utilities

            // iOS-specific Info.plist property keys
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*] = YES
            INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*] = YES
            INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*] = YES
            INFOPLIST_KEY_UIStatusBarStyle[sdk=iphone*] = UIStatusBarStyleDefault
            INFOPLIST_KEY_UISupportedInterfaceOrientations[sdk=iphone*] = UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown

            // Development team ID for on-device testing
            CODE_SIGNING_REQUIRED = NO
            CODE_SIGN_STYLE = Automatic
            CODE_SIGN_ENTITLEMENTS = \(Capabilities_entitlements_path)
            //CODE_SIGNING_IDENTITY = -
            //DEVELOPMENT_TEAM =

            """

            let xcconfigURL = projectURL.appending(path: primaryModuleName + ".xcconfig")
            try configContents.write(to: xcconfigURL, atomically: true, encoding: .utf8)
            let xcconfigFileName = xcconfigURL.lastPathComponent


            // Sources/PlaygroundApp/PlaygroundAppMain.swift
            let appMainContents = """
            \(sourceHeader)import SwiftUI
            import \(primaryModuleName)

            /// The entry point to the app simply loads the App implementation from SPM module.
            @main struct AppMain: App, \(primaryModuleAppTarget) {
            }

            """
            let primaryModuleAppMainURL = projectURL.appending(path: primaryModuleAppMainPath)
            try FileManager.default.createDirectory(at: primaryModuleAppMainURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try appMainContents.write(to: primaryModuleAppMainURL, atomically: true, encoding: .utf8)

            // Sources/Playground/PlaygroundApp.swift
            let appExtContents = """
            \(sourceHeader)import Foundation
            import OSLog
            import SwiftUI

            let logger: Logger = Logger(subsystem: "\(appid)", category: "\(primaryModuleName)")

            /// The Android SDK number we are running against, or `nil` if not running on Android
            let androidSDK = ProcessInfo.processInfo.environment["android.os.Build.VERSION.SDK_INT"].flatMap({ Int($0) })

            /// The shared top-level view for the app, loaded from the platform-specific App delegates below.
            ///
            /// The default implementation merely loads the `ContentView` for the app and logs a message.
            struct RootView : View {
                var body: some View {
                    ContentView()
                        .task {
                            logger.log("Welcome to Skip on \\(androidSDK != nil ? "Android" : "iOS")!")
                            logger.warning("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
                        }
                }
            }

            #if !SKIP
            public protocol \(primaryModuleAppTarget) : App {
            }

            /// The entry point to the \(primaryModuleName) app.
            /// The concrete implementation is in the \(primaryModuleName)App module.
            public extension \(primaryModuleAppTarget) {
                var body: some Scene {
                    WindowGroup {
                        RootView()
                    }
                }
            }

            #else
            import android.Manifest
            import android.app.Application
            import androidx.activity.compose.setContent
            import androidx.appcompat.app.AppCompatActivity
            import androidx.compose.foundation.isSystemInDarkTheme
            import androidx.compose.foundation.layout.fillMaxSize
            import androidx.compose.foundation.layout.Box
            import androidx.compose.material3.MaterialTheme
            import androidx.compose.material3.darkColorScheme
            import androidx.compose.material3.dynamicDarkColorScheme
            import androidx.compose.material3.dynamicLightColorScheme
            import androidx.compose.material3.lightColorScheme
            import androidx.compose.runtime.saveable.rememberSaveableStateHolder
            import androidx.compose.ui.Alignment
            import androidx.compose.ui.Modifier
            import androidx.compose.ui.platform.LocalContext
            import androidx.core.app.ActivityCompat

            /// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
            public class AndroidAppMain : Application {
                public init() {
                }

                public override func onCreate() {
                    super.onCreate()
                    logger.info("starting app")
                    ProcessInfo.launch(applicationContext)
                }
            }

            /// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
            public class MainActivity : AppCompatActivity {
                public init() {
                }

                public override func onCreate(savedInstanceState: android.os.Bundle?) {
                    super.onCreate(savedInstanceState)

                    setContent {
                        let saveableStateHolder = rememberSaveableStateHolder()
                        saveableStateHolder.SaveableStateProvider(true) {
                            Box(modifier: Modifier.fillMaxSize(), contentAlignment: Alignment.Center) {
                                MaterialThemedRootView()
                            }
                        }
                    }

                    // Example of requesting permissions on startup. 
                    // These must match the permissions in the AndroidManifest.xml file.
                    //let permissions = listOf(
                    //    Manifest.permission.ACCESS_COARSE_LOCATION,
                    //    Manifest.permission.ACCESS_FINE_LOCATION
                    //    Manifest.permission.CAMERA,
                    //    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    //)
                    //let requestTag = 1
                    //ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
                }

                public override func onSaveInstanceState(bundle: android.os.Bundle) {
                    super.onSaveInstanceState(bundle)
                }

                public override func onRestoreInstanceState(bundle: android.os.Bundle) {
                    // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
                    logger.info("onRestoreInstanceState")
                    super.onRestoreInstanceState(bundle)
                }

                public override func onRestart() {
                    logger.info("onRestart")
                    super.onRestart()
                }

                public override func onStart() {
                    logger.info("onStart")
                    super.onStart()
                }

                public override func onResume() {
                    logger.info("onResume")
                    super.onResume()
                }

                public override func onPause() {
                    logger.info("onPause")
                    super.onPause()
                }

                public override func onStop() {
                    logger.info("onStop")
                    super.onStop()
                }

                public override func onDestroy() {
                    logger.info("onDestroy")
                    super.onDestroy()
                }

                public override func onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
                    super.onRequestPermissionsResult(requestCode, permissions, grantResults)
                    logger.info("onRequestPermissionsResult: \\(requestCode)")
                }
            }

             @Composable func MaterialThemedRootView() {
                let context = LocalContext.current
                let darkMode = isSystemInDarkTheme()
                // Dynamic color is available on Android 12+
                let dynamicColor = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S

                let colorScheme = dynamicColor
                    ? (darkMode ? dynamicDarkColorScheme(context) : dynamicLightColorScheme(context))
                    : (darkMode ? darkColorScheme() : lightColorScheme())

                MaterialTheme(colorScheme: colorScheme) {
                    RootView().Compose()
                }
            }

            #endif

            """

            let appModuleApplicationStubFileBase = primaryModuleAppTarget + ".swift"
            let appModuleApplicationStubFilePath = primaryModuleSources + "/" + appModuleApplicationStubFileBase

            let appModuleApplicationStubFileURL = projectURL.appending(path: appModuleApplicationStubFilePath)
            try FileManager.default.createDirectory(at: appModuleApplicationStubFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try appExtContents.write(to: appModuleApplicationStubFileURL, atomically: true, encoding: .utf8)


            // Sources/Playground/PlaygroundApp.swift
            let contentViewContents = """
            \(sourceHeader)import SwiftUI

            public struct ContentView: View {
                @AppStorage("setting") var setting = true

                public init() {
                }

                public var body: some View {
                    TabView {
                        VStack {
                            Text("Welcome Skipper!")
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                        }
                        .font(.largeTitle)
                        .tabItem { Label("Welcome", systemImage: "heart.fill") }

                        NavigationStack {
                            List {
                                ForEach(1..<1_000) { i in
                                    NavigationLink("Home \\(i)", value: i)
                                }
                            }
                            .navigationTitle("Navigation")
                            .navigationDestination(for: Int.self) { i in
                                Text("Destination \\(i)")
                                    .font(.title)
                                    .navigationTitle("Navigation \\(i)")
                            }
                        }
                        .tabItem { Label("Home", systemImage: "house.fill") }

                        Form {
                            Text("Settings")
                                .font(.largeTitle)
                            Toggle("Option", isOn: $setting)
                        }
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    }
                }
            }

            """

            let contentViewFileBase = "ContentView.swift"
            let contentViewRelativePath = primaryModuleSources + "/" + contentViewFileBase

            let contentViewURL = projectURL.appending(path: contentViewRelativePath)
            try FileManager.default.createDirectory(at: contentViewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contentViewContents.write(to: contentViewURL, atomically: true, encoding: .utf8)


            let Assets_xcassets_name = "Assets.xcassets"
            let Assets_xcassets_path = appModule_Metadata_Path + "/" + Assets_xcassets_name
            let Assets_xcassets_URL = try projectURL.append(path: Assets_xcassets_path, create: true)

            let Assets_xcassets_Contents_URL = Assets_xcassets_URL.appendingPathComponent("Contents.json", isDirectory: false)
            let Assets_xcassets_Contents = """
            {
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }
            """
            try Assets_xcassets_Contents.write(to: Assets_xcassets_Contents_URL, atomically: true, encoding: .utf8)

            let Assets_xcassets_AccentColor = try Assets_xcassets_URL.append(path: "AccentColor.colorset", create: true)
            let Assets_xcassets_AccentColor_Contents = """
            {
              "colors" : [
                {
                  "idiom" : "universal"
                }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }
            """


            let Assets_xcassets_AccentColor_ContentsURL = Assets_xcassets_AccentColor.appending(path: "Contents.json")
            try Assets_xcassets_AccentColor_Contents.write(to: Assets_xcassets_AccentColor_ContentsURL, atomically: true, encoding: .utf8)

            let Assets_xcassets_AppIcon = try Assets_xcassets_URL.append(path: "AppIcon.appiconset", create: true)
            let Assets_xcassets_AppIcon_Cotntents = """
            {
              "images" : [
                {
                  "idiom" : "universal",
                  "platform" : "ios",
                  "size" : "1024x1024"
                }
              ],
              "info" : {
                "author" : "xcode",
                "version" : 1
              }
            }

            """
            let Assets_xcassets_AppIcon_CotntentsURL = Assets_xcassets_AppIcon.appending(path: "Contents.json")
            try Assets_xcassets_AppIcon_Cotntents.write(to: Assets_xcassets_AppIcon_CotntentsURL, atomically: true, encoding: .utf8)


            let xcodeProjectContents = createXcodeProj(appModuleName: appModuleName, appMainSwiftFileName: appMainSwiftFileName, Assets_xcassets_name: Assets_xcassets_name, xcconfigFileName: xcconfigFileName, primaryModuleAppTarget: primaryModuleAppTarget, primaryModuleAppMainPath: primaryModuleAppMainPath, Assets_xcassets_path: Assets_xcassets_path, Capabilities_entitlements_name: Capabilities_entitlements_name, Capabilities_entitlements_path: Capabilities_entitlements_path)
            let xcodeProjectPbxprojURL = xcodeProjectFolder.appending(path: "project.pbxproj")
            // change spaces to tabs in the pbxproj, since that is what Xcode will do when it saves it
            try xcodeProjectContents.replacingOccurrences(of: "    ", with: "\t").write(to: xcodeProjectPbxprojURL, atomically: true, encoding: .utf8)
        }

        // the initial build/test is done with debug configuration regardless of the configuration setting; this is because unit tests don't always run correctly in release mode
        let debugConfiguration = "debug"

        if build == true || apk == true {
            await run(with: out, "\(re)Resolve dependencies", ["swift", "package", "resolve", "-v", "--package-path", projectURL.path])

            // we need to build regardless of preference in order to build the apk
            await run(with: out, "\(re)Build \(projectName)", ["swift", "build", "-v", "-c", debugConfiguration, "--package-path", projectURL.path])
        }

        if test == true {
            try await runSkipTests(in: projectURL, configuration: debugConfiguration, swift: true, kotlin: true, with: out)
        }

        // the output URLs to any ipa/apk artifacts that are generated by the build
        var artifactHashes: [URL: String?] = [:]

        if ipa == true {
            // xcodebuild -derivedDataPath .build/DerivedData -skipPackagePluginValidation -archivePath "${ARCHIVE_PATH}" -configuration "${CONFIGURATION}" -scheme "${SKIP_MODULE}" -sdk "iphoneos" -destination "generic/platform=iOS" -jobs 1 archive CODE_SIGNING_ALLOWED=NO
            let archiveBasePath = buildFolderName + "/Skip/artifacts/" + configuration.capitalized

            let archivePath = archiveBasePath + "/" + primaryModuleAppTarget + ".xcarchive"
            let ipaPath = archiveBasePath + "/" + primaryModuleName + cfgSuffix + ".ipa"
            let ipaURL = projectURL.appending(path: ipaPath)

            // note that derivedDataPath and archivePath are relative to CWD rather than
            let fullArchivePath = projectURL.path + "/" + archivePath
            let fullDerivedDataPath = projectURL.path + "/" + buildFolderName + "/DerivedData"

            await run(with: out, "\(re)Archive iOS ipa", [
                "xcodebuild",
                "-project", xcodeProjectFolder.path,
                "-derivedDataPath", fullDerivedDataPath,
                "-skipPackagePluginValidation",
                "-archivePath", fullArchivePath,
                "-configuration", configuration.capitalized,
                "-scheme", primaryModuleAppTarget,
                "-sdk", "iphoneos",
                "-destination", "generic/platform=iOS",
                "archive",
                "CODE_SIGNING_ALLOWED=NO",
                "ZERO_AR_DATE=1", // excludes timestamps from archives for build reproducibility
            ], additionalEnvironment: ["SKIP_ZERO": "1"]) // SKIP_ZERO builds without Skip dependency libraries


            let archiveAppPath = archivePath + "/Products/Applications/" + primaryModuleAppTarget + ".app"
            let archiveAppURL = projectURL.appending(path: archiveAppPath)

            // Create an ipa (zip) file of the app contents

            // need to first copy the contents over to a "Payload" folder, since the root of the .ipa needs to be "Payload"
            let archiveAppPayloadURL = archiveAppURL
                .deletingLastPathComponent()
                .appendingPathComponent("Payload", isDirectory: true)
            try FileManager.default.createDirectory(at: archiveAppPayloadURL, withIntermediateDirectories: false)
            let archiveAppContentsURL = archiveAppPayloadURL
                .appendingPathComponent(archiveAppURL.lastPathComponent, isDirectory: true)

            try FileManager.default.copyItem(at: archiveAppURL, to: archiveAppContentsURL)
            try FileManager.default.zeroFileTimes(under: archiveAppPayloadURL)

            await run(with: out, "\(re)Assemble \(ipaURL.lastPathComponent)", ["zip", "-9", "-r", ipaURL.path, archiveAppPayloadURL.lastPathComponent], in: archiveAppPayloadURL.deletingLastPathComponent())

            await checkFile(ipaURL, with: out, title: "\(re)Verifying \(ipaURL.lastPathComponent)") { url in
                CheckStatus(status: .pass, message: try "Verify \(ipaURL.lastPathComponent) \(url.fileSizeString)")
            }

            if returnHashes {
                func checkArtifactHash(url: URL) throws -> CheckStatus {
                    let ipaHash = try url.SHA256Hash()
                    artifactHashes[ipaURL] = ipaHash
                    return CheckStatus(status: .pass, message: "IPA SHA256: \(ipaHash)")
                }

                await checkFile(ipaURL, with: out, title: "\(re)Checksum Archive", handle: checkArtifactHash)
            }
        }

        if apk == true { // assemble the .apk
            let env = ProcessInfo.processInfo.environmentWithDefaultToolPaths // environment that includes a default ANDROID_HOME

            let gradleProjectDir = projectURL.path + "/" + buildFolderName + "/plugins/outputs/" + projectName + "/" + primaryModuleName + "/skipstone"
            let relativeBuildDir = buildFolderName + "/" + projectName

            let action = "assemble" + configuration.capitalized // turn "debug" into "Debug" and "release" into "Release"
            await run(with: out, "Assembling Android apk", ["gradle", action, "--console=plain", "--info", "--project-dir", gradleProjectDir, "-PbuildDir=" + relativeBuildDir], environment: env)
            //{ result in (result, nil) }

            // the expected path for the gradle output folder of the assemble action
            let outputsPath = gradleProjectDir + "/" + primaryModuleName  + "/" + relativeBuildDir + "/outputs"

            // for example: skipapp-playground/.build/plugins/outputs/skipapp-playground/Playground/skipstone/Playground/.build/skipapp-playground/outputs/apk/release/Playground-release.apk
            let unsigned = configuration == "release" ? "-unsigned" : "" // we do not sign the release builds for reproducibility, which leads to them having the "-unsigned" suffix

            let apkTitle = primaryModuleName + cfgSuffix + ".apk" // the name of the .apk for reporting purposes (don't include the -unsigned)
            let apkPath = outputsPath + "/apk/" + configuration + "/" + primaryModuleName + cfgSuffix + unsigned + ".apk"
            let apkURL = URL(fileURLWithPath: apkPath, isDirectory: false)

            await checkFile(apkURL, with: out, title: "Verify \(apkTitle)") { url in
                return CheckStatus(status: .pass, message: try "Verify \(apkTitle) \(url.fileSizeString)")
            }

            if returnHashes {
                func checkArtifactHash(url: URL) throws -> CheckStatus {
                    let apkHash = try url.SHA256Hash()
                    artifactHashes[apkURL] = apkHash
                    return CheckStatus(status: .pass, message: "APK SHA256: \(apkHash)")
                }

                await checkFile(apkURL, with: out, title: "\(re)Checksum Archive", handle: checkArtifactHash)
            }
        }

        if gitRepo == true {
            func createGitRepo(url: URL) throws -> CheckStatus {
                // create the .gitignore file
                let gitignore = """
                .*.swp
                .DS_Store
                .build
                build
                /Packages
                xcuserdata/
                DerivedData/
                .swiftpm/configuration/registries.json
                .swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
                .netrc

                """

                try gitignore.write(to: projectURL.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
                return CheckStatus(status: .pass, message: "Create git repository")
            }

            await checkFile(projectURL, with: out, title: "Create git repository", handle: createGitRepo)
        }

        if verify {
            try await performVerifyCommand(project: projectPath.pathString, with: out)
        }

        if showTree {
            await showFileTree(in: projectPath, with: out)
        }

        return (appid != nil ? xcodeProjectFolder : projectURL.appendingPathComponent("Package.swift", isDirectory: false), artifactHashes)
    }

    func initSkipLibrary(projectName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, verify: Bool, chain: Bool, gitRepo: Bool, free: Bool, zero skipZeroSupport: Bool, app: Bool, moduleTests: Bool, validatePackage: Bool, packageResolved packageResolvedURL: URL?, with out: MessageQueue) async throws -> URL {
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder.path, isDirectory: &isDir) {
            throw InitError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw InitError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolderURL = outputFolder.appendingPathComponent(projectName, isDirectory: true)
        if FileManager.default.fileExists(atPath: projectFolderURL.path) {
            throw InitError(errorDescription: "Specified project path already exists: \(projectFolderURL.path)")
        }

        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        let sourcesURL = try projectFolderURL.append(path: "Sources", create: true)

        let sourceHeader = free ? licenseLGPLHeader : ""

        // the part of a target parameter that will only include skip when zero is not set
        //let skipCondition = skipZeroSupport ? ", condition: skip" : "" // we don't use the condition parameter of target because it excludes
        let skipPluginArray = skipZeroSupport ? "skipstone" : #"[.plugin(name: "skipstone", package: "skip")]"#

        var products = """
            products: [

        """

        var targets = """
            targets: [

        """


#if DEBUG
        let skipPackageVersion = "0.0.0"
#else
        let skipPackageVersion = skipVersion
#endif
        var packageHeader = """
        // swift-tools-version: 5.9

        """

        if free {
            packageHeader += licenseLGPLHeader
        } else {
            packageHeader += """
            // This is a Skip (https://skip.tools) package,
            // containing a Swift Package Manager project
            // that will use the Skip build plugin to transpile the
            // Swift Package, Sources, and Tests into an
            // Android Gradle Project with Kotlin sources and JUnit tests.
            
            """
        }

        packageHeader += """
        import PackageDescription
        \(skipZeroSupport ? """
        import Foundation

        // Set SKIP_ZERO=1 to build without Skip libraries
        let zero = ProcessInfo.processInfo.environment["SKIP_ZERO"] != nil
        let skipstone = !zero ? [Target.PluginUsage.plugin(name: "skipstone", package: "skip")] : []
        
        """ : "")
        """

        var packageDependencies: [String] = [
            ".package(url: \"https://source.skip.tools/skip.git\", from: \"\(skipPackageVersion)\")"
        ]

        for moduleIndex in modules.indices {
            let module = modules[moduleIndex]
            let moduleName = module.moduleName
            // determine the package name of the app module to reference the .MainActivity class; we simply de-camel-case and hyphenate the module name, but in the future we may permit customization in the skip.yml file
            let modulePackageName = KotlinTranslator.packageName(forModule: moduleName)

            // the isAppModule is the initial module in the list when we specify we want to create an app module
            let isAppModule = app == true && moduleIndex == modules.startIndex
            // the model module is the second in the chain
            let isModelModule = app == true && moduleIndex == modules.startIndex + 1
            // this is the final module in the chain, which will add a dependency on SkipFoundation
            let isFinalModule = moduleIndex == modules.endIndex - 1

            // the subsequent module
            let nextModule = moduleIndex < modules.endIndex - 1 ? modules[moduleIndex+1] : nil
            let nextModuleName = nextModule?.moduleName

            let sourceDir = try sourcesURL.append(path: moduleName, create: true)
            let sourceSkipDir = try sourceDir.append(path: "Skip", create: true)

            let sourceSkipYamlFile = sourceSkipDir.appending(path: "skip.yml")

            let skipYamlGeneric = """
            # Configuration file for https://skip.tools project
            #
            # Kotlin dependencies and Gradle build options for this module can be configured here
            #build:
            #  contents:
            #    - block: 'dependencies'
            #      contents:
            #        - 'implementation("androidx.compose.runtime:runtime")'

            """

            let skipYamlApp = """
            # Configuration file for https://skip.tools project
            #
            # This skip.yml file is associated with an Android App project,
            # and buiding it will create an installable .apk file.
            #
            # The app's metadata is derived from the top-level
            # ModuleName.xcconfig file, which in turn are used to generate both the
            # AndroidManifest.xml (for the Android apk) and the
            # Info.plist (for the iOS ipa).
            build:
              contents:
                - block: 'android'
                  remove:
                    - 'namespace = group as String'
                  contents:
                    - 'namespace = "\(modulePackageName)"'
                    - block: 'defaultConfig'
                      contents:
                        # Android app config and AndroidManifest.xml metadata can be specified here
                        - 'applicationId = System.getenv("PRODUCT_BUNDLE_IDENTIFIER") ?: "\(modulePackageName)"'
                    - block: 'buildFeatures'
                      contents:
                        - 'buildConfig = true'
                    - block: 'buildTypes'
                      contents:
                        - block: 'release'
                          contents:
                            # by default create an -unsigned.apk; for publishing to an app store, a valid keystore will need to be provided
                            - 'signingConfig = signingConfigs.findByName("release")'
                            # enabling minification reduces compose dependency classe size ~85%
                            - 'isMinifyEnabled = true'
                            - 'isShrinkResources = true'
                            - 'isDebuggable = true'
                            - 'proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")'
            """

            try (isAppModule ? skipYamlApp : skipYamlGeneric).write(to: sourceSkipYamlFile, atomically: true, encoding: .utf8)

            let sourceSwiftFile = sourceDir.appending(path: "\(moduleName).swift")
            try """
            \(sourceHeader)public class \(moduleName)Module {
            }

            """.write(to: sourceSwiftFile, atomically: true, encoding: .utf8)

            var resourcesAttribute: String = ""
            if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                let sourceResourcesDir = try sourceDir.append(path: resourceFolder, create: true)
                let sourceResourcesFile = sourceResourcesDir.appending(path: "Localizable.xcstrings")
                try """
                {
                  "sourceLanguage" : "en",
                  "strings" : {},
                  "version" : "1.0"
                }
                """.write(to: sourceResourcesFile, atomically: true, encoding: .utf8)
            }


            if moduleTests {
                let testsURL = try projectFolderURL.append(path: "Tests", create: true)
                let testDir = try testsURL.append(path: moduleName + "Tests", create: true)
                let testSkipDir = try testDir.append(path: "Skip", create: true)
                let testSwiftFile = testDir.appending(path: "\(moduleName)Tests.swift")

                try """
                \(sourceHeader)import XCTest
                import OSLog
                import Foundation
                @testable import \(moduleName)

                let logger: Logger = Logger(subsystem: "\(moduleName)", category: "Tests")

                @available(macOS 13, *)
                final class \(moduleName)Tests: XCTestCase {
                    func test\(moduleName)() throws {
                        logger.log("running test\(moduleName)")
                        XCTAssertEqual(1 + 2, 3, "basic test")
                        \(resourceFolder.flatMap { folderName in
                """

                        // load the TestData.json file from the \(folderName) folder and decode it into a struct
                        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
                        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
                        XCTAssertEqual("\(moduleName)", testData.testModuleName)
                """
                        } ?? "")
                    }
                }
                \(resourceFolder.flatMap { folderName in
                """

                struct TestData : Codable, Hashable {
                    var testModuleName: String
                }
                """ } ?? "")
                """.write(to: testSwiftFile, atomically: true, encoding: .utf8)

                let testSkipModuleFile = testDir.appending(path: "XCSkipTests.swift")
                try """
                \(sourceHeader)#if os(macOS) // Skip transpiled tests only run on macOS targets
                import SkipTest

                /// This test case will run the transpiled tests for the Skip module.
                @available(macOS 13, macCatalyst 16, *)
                final class XCSkipTests: XCTestCase, XCGradleHarness {
                    public func testSkipModule() async throws {
                        // Run the transpiled JUnit tests for the current test module.
                        // These tests will be executed locally using Robolectric.
                        // Connected device or emulator tests can be run by setting the
                        // `ANDROID_SERIAL` environment variable to an `adb devices`
                        // ID in the scheme's Run settings.
                        //
                        // Note that it isn't currently possible to filter the tests to run.
                        try await runGradleTests()
                    }
                }
                #endif
                """.write(to: testSkipModuleFile, atomically: true, encoding: .utf8)

                let skipYamlAppTests = """
                # Configuration file for https://skip.tools project
                #build:
                #  contents:
                """
                let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
                try (isAppModule ? skipYamlAppTests : skipYamlGeneric).write(to: testSkipYamlFile, atomically: true, encoding: .utf8)

                if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                    let testResourcesDir = try testDir.append(path: resourceFolder, create: true)
                    let testResourcesFile = testResourcesDir.appending(path: "TestData.json")
                    try """
                    {
                      "testModuleName": "\(moduleName)"
                    }
                    """.write(to: testResourcesFile, atomically: true, encoding: .utf8)

                    resourcesAttribute = ", resources: [.process(\"\(resourceFolder)\")]"
                }
            }

            products += """
                    .library(name: "\(moduleName)", type: .dynamic, targets: ["\(moduleName)"]),

            """

            if isAppModule {
                let androidManifestContents = """
                <?xml version="1.0" encoding="utf-8"?>
                <!-- This AndroidManifest.xml template was generated for the Skip module \(moduleName) -->
                <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                    <!-- example permissions for using device location -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/> -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/> -->

                    <!-- permissions needed for using the internet or an embedded WebKit browser -->
                    <!-- <uses-permission android:name="android.permission.INTERNET" /> -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" /> -->

                    <application
                        android:label="${PRODUCT_NAME}"
                        android:name=".AndroidAppMain"
                        android:allowBackup="true">
                        <activity
                            android:name=".MainActivity"
                            android:exported="true"
                            android:theme="@style/Theme.AppCompat.DayNight.NoActionBar"
                            android:windowSoftInputMode="adjustResize">
                            <intent-filter>
                                <action android:name="android.intent.action.MAIN" />
                                <category android:name="android.intent.category.LAUNCHER" />
                            </intent-filter>
                        </activity>
                    </application>
                </manifest>

                """
                let androidManifestFile = sourceSkipDir.appending(path: "AndroidManifest.xml")
                try androidManifestContents.write(to: androidManifestFile, atomically: true, encoding: .utf8)
            }

            var moduleDeps: [String] = []
            if let nextModuleName = nextModuleName, chain == true {
                moduleDeps.append("\"" + nextModuleName + "\"") // the internal module names are just referred to by string
            }

            var modDeps = module.dependencies
            if modDeps.isEmpty {
                // add implicit dependency on SkipUI (for app target), SkipModel, and SkipFoundation, based in their position in the chain
                if isAppModule {
                    modDeps.append(PackageModule(repositoryName: "skip-ui", moduleName: "SkipUI"))
                } else if isFinalModule || chain == false {
                    // only add SkipFoundation to the innermost module, or else
                    modDeps.append(PackageModule(repositoryName: "skip-foundation", moduleName: "SkipFoundation"))
                }

                // in addition to a top-level dependency on SkipUI and a bottom-level dependency on SkipFoundation, a secondary module will also have a dependency on SkipModel for observability
                if isModelModule {
                    modDeps.append(PackageModule(repositoryName: "skip-model", moduleName: "SkipModel"))
                }
            }
            var skipModuleDeps: [String] = []
            for modDep in modDeps {
                if let repoName = modDep.repositoryName {
                    let depVersion = modDep.repositoryVersion ?? "0.0.0"
                    let packDep = ".package(url: \"https://source.skip.tools/\(repoName).git\", from: \"\(depVersion)\")"
                    if !packageDependencies.contains(packDep) {
                        packageDependencies.append(packDep)
                    }
                    let dep = ".product(name: \"\(modDep.moduleName)\", package: \"\(repoName)\")"
                    if !skipModuleDeps.contains(dep) {
                        skipModuleDeps.append(dep)
                    }
                }
            }

            // if we are using the SKIP_ZERO conditional, then split up the dependencies and only include the skip dependencies conditionally
            let bracket = { "[" + $0 + "]" }
            let interModuleDep = moduleDeps.joined(separator: ", ")
            let skipModuleDep = skipModuleDeps.joined(separator: ", ")
            let zeroSkipModuleCondition = skipZeroSupport && !skipModuleDeps.isEmpty ? "(zero ? [] : " + bracket(skipModuleDep) + ")" : bracket(skipModuleDep)

            let moduleDep = !interModuleDep.isEmpty && !skipModuleDep.isEmpty
                ? (!skipZeroSupport
                   ? bracket(interModuleDep + ", " + skipModuleDep)
                   : bracket(interModuleDep) + " + " + zeroSkipModuleCondition)
                : !skipModuleDep.isEmpty 
                    ? (skipZeroSupport ? zeroSkipModuleCondition : bracket(skipModuleDep))
                : bracket(interModuleDep)

            targets += """
                    .target(name: "\(moduleName)", dependencies: \(moduleDep)\(resourcesAttribute), plugins: \(skipPluginArray)),

            """

            if moduleTests {
                let skipTestProduct = #".product(name: "SkipTest", package: "skip")"#
                let skipTestDependency = skipZeroSupport
                    ? "] + (zero ? [] : [\(skipTestProduct)])"
                    : ", \(skipTestProduct)]"

                targets += """
                        .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)"\(skipTestDependency)\(resourcesAttribute), plugins: \(skipPluginArray)),

                """
            }
        }

        products += """
            ]
        """
        targets += """
            ]
        """

        let dependencies = "    dependencies: [\n        " + packageDependencies.joined(separator: ",\n        ") + "\n    ]"

        let packageSource = """
        \(packageHeader)
        let package = Package(
            name: "\(projectName)",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
        \(products),
        \(dependencies),
        \(targets)
        )

        """

        let packageSwiftURL = projectFolderURL.appending(path: "Package.swift")
        try packageSource.write(to: packageSwiftURL, atomically: true, encoding: .utf8)

        // now snapshot the file tree for inclusion in the README
        // let fileTree = try localFileSystem.treeASCIIRepresentation(at: projectFolderURL.absolutePath, hideHiddenFiles: true)

        // if we've specified a Package.resolved source file, simply copy it over
        if let packageResolvedURL = packageResolvedURL {
            try FileManager.default.copyItem(at: packageResolvedURL, to: projectFolderURL.appending(path: "Package.resolved"))
        }

        let readmeURL = projectFolderURL.appending(path: "README.md")
        let primaryModuleName = modules.first?.moduleName ?? "Module"

        let libREADME = """
        # \(primaryModuleName)

        This is a \(free ? "free " : "")[Skip](https://skip.tools) Swift/Kotlin library project containing the following modules:

        \(modules.map(\.moduleName).joined(separator: "\n"))

        ## Building

        This project is a \(free ? "free " : "")Swift Package Manager module that uses the
        [Skip](https://skip.tools) plugin to transpile Swift into Kotlin.

        Building the module requires that Skip be installed using 
        [Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.
        This will also install the necessary build prerequisites:
        Kotlin, Gradle, and the Android build tools.

        ## Testing

        The module can be tested using the standard `swift test` command
        or by running the test target for the macOS destination in Xcode,
        which will run the Swift tests as well as the transpiled
        Kotlin JUnit tests in the Robolectric Android simulation environment.

        Parity testing can be performed with `skip test`,
        which will output a table of the test results for both platforms.

        """


        let appREADME = """
        # \(primaryModuleName)

        This is a \(free ? "free " : "")[Skip](https://skip.tools) dual-platform app project.
        It builds a native app for both iOS and Android.

        ## Building

        This project is both a stand-alone Swift Package Manager module,
        as well as an Xcode project that builds and transpiles the project
        into a Kotlin Gradle project for Android using the Skip plugin.

        Building the module requires that Skip be installed using
        [Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.

        This will also install the necessary transpiler prerequisites:
        Kotlin, Gradle, and the Android build tools.

        Installation prerequisites can be confirmed by running `skip checkup`.

        ## Testing

        The module can be tested using the standard `swift test` command
        or by running the test target for the macOS desintation in Xcode,
        which will run the Swift tests as well as the transpiled
        Kotlin JUnit tests in the Robolectric Android simulation environment.

        Parity testing can be performed with `skip test`,
        which will output a table of the test results for both platforms.

        ## Running

        Xcode and Android Studio must be downloaded and installed in order to
        run the app in the iOS simulator / Android emulator.
        An Android emulator must already be running, which can be launched from 
        Android Stuido's Device Manager.

        To run both the Swift and Kotlin apps simultaneously, 
        launch the \(primaryModuleName)App target from Xcode.
        A build phases runs the "Launch Android APK" script that
        will deploy the transpiled app a running Android emulator or connected device.
        Logging output for the iOS app can be viewed in the Xcode console, and in
        Android Studio's logcat tab for the transpiled Kotlin app.

        """

        try (app ? appREADME : libREADME).write(to: readmeURL, atomically: true, encoding: .utf8)

        if free == true {
            try licenseLGPL.write(to: projectFolderURL.appending(path: "LICENSE.LGPL"), atomically: true, encoding: .utf8)
        }

        if validatePackage {
            let packageJSONString = try await run(with: out, "Create project \(projectName)", ["swift", "package", "dump-package", "--package-path", projectFolderURL.path]).get().stdout

            let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
            _ = packageJSON
        }

        return projectFolderURL
    }
}

extension ToolOptionsCommand {
    /// Perform a monitor check on the given URL
    func check<T, U>(_ item: T, with out: MessageQueue, title: String, handle: @escaping (T) throws -> U) async -> Result<U, Error> {
        await outputOptions.monitor(with: out, title, resultHandler: { result in
            return (nil, nil) as (result: Result<U, any Error>?, message: MessageBlock?)
        }) { line in
            try handle(item)
        }
    }


    /// Perform a monitor check on the given URL
    func checkFile(_ url: URL, with out: MessageQueue, title: String, handle: @escaping (URL) throws -> CheckStatus) async {
        await outputOptions.monitor(with: out, title, resultHandler: { result in
            do {
                if let resultURL = try result?.get() {
                    let handleResult = try handle(resultURL)
                    return (result, MessageBlock(status: handleResult.status, handleResult.message))
                } else {
                    return (result, nil)
                }
            } catch {
                return (Result.failure(error), nil)
            }
        }) { loggingHandler in
            return url
        }
    }

}

struct CheckStatus {
    let status: MessageBlock.Status
    let message: String
}

struct PackageModule {
    var moduleName: String
    var organizationName: String? = nil
    var repositoryName: String? = nil
    var repositoryVersion: String? = nil
    var dependencies: [PackageModule] = []

    init(repositoryName: String, moduleName: String) {
        self.repositoryName = repositoryName
        self.moduleName = moduleName
    }

    init(moduleName: String) {
        self.moduleName = moduleName
    }

    init(parse: String) throws {
        let parts = parse.split(separator: ":").map(\.description)
        self.moduleName = parts.first ?? parse
        for dep in parts.dropFirst() {
            // parse PlaygroundModel:skiptools/skip-model/SkipModel:skip-foundation@0.1.0/SkipFoundation
            var depParts = dep.split(separator: "/").map(\.description)
            let moduleName = depParts.last ?? dep // e.g., "SkipFoundation"
            depParts.removeLast()

            var depModule = PackageModule(moduleName: moduleName)
            defer { self.dependencies.append(depModule) }

            if !depParts.isEmpty {
                let orgName: String
                let repoPart: String
                if depParts.count == 1 {
                    orgName = "skiptools"
                    repoPart = depParts[0]
                } else {
                    orgName = depParts[0]
                    repoPart = depParts[1]
                }

                let repoName: String
                let repoVersion: String?

                let repoParts = repoPart.split(separator: "@")
                if repoParts.count > 1 { // see if the version is specified
                    repoName = repoParts.first?.description ?? repoPart
                    repoVersion = repoParts.last?.description
                } else { // no version specified
                    repoName = repoPart
                    repoVersion = nil
                }

                depModule.organizationName = orgName
                depModule.repositoryName = repoName
                depModule.repositoryVersion = repoVersion
            }
        }
    }
}


struct InitError : LocalizedError {
    var errorDescription: String?
}



let licenseLGPL = """
                   GNU LESSER GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.


  This version of the GNU Lesser General Public License incorporates
the terms and conditions of version 3 of the GNU General Public
License, supplemented by the additional permissions listed below.

  0. Additional Definitions.

  As used herein, "this License" refers to version 3 of the GNU Lesser
General Public License, and the "GNU GPL" refers to version 3 of the GNU
General Public License.

  "The Library" refers to a covered work governed by this License,
other than an Application or a Combined Work as defined below.

  An "Application" is any work that makes use of an interface provided
by the Library, but which is not otherwise based on the Library.
Defining a subclass of a class defined by the Library is deemed a mode
of using an interface provided by the Library.

  A "Combined Work" is a work produced by combining or linking an
Application with the Library.  The particular version of the Library
with which the Combined Work was made is also called the "Linked
Version".

  The "Minimal Corresponding Source" for a Combined Work means the
Corresponding Source for the Combined Work, excluding any source code
for portions of the Combined Work that, considered in isolation, are
based on the Application, and not on the Linked Version.

  The "Corresponding Application Code" for a Combined Work means the
object code and/or source code for the Application, including any data
and utility programs needed for reproducing the Combined Work from the
Application, but excluding the System Libraries of the Combined Work.

  1. Exception to Section 3 of the GNU GPL.

  You may convey a covered work under sections 3 and 4 of this License
without being bound by section 3 of the GNU GPL.

  2. Conveying Modified Versions.

  If you modify a copy of the Library, and, in your modifications, a
facility refers to a function or data to be supplied by an Application
that uses the facility (other than as an argument passed when the
facility is invoked), then you may convey a copy of the modified
version:

   a) under this License, provided that you make a good faith effort to
   ensure that, in the event an Application does not supply the
   function or data, the facility still operates, and performs
   whatever part of its purpose remains meaningful, or

   b) under the GNU GPL, with none of the additional permissions of
   this License applicable to that copy.

  3. Object Code Incorporating Material from Library Header Files.

  The object code form of an Application may incorporate material from
a header file that is part of the Library.  You may convey such object
code under terms of your choice, provided that, if the incorporated
material is not limited to numerical parameters, data structure
layouts and accessors, or small macros, inline functions and templates
(ten or fewer lines in length), you do both of the following:

   a) Give prominent notice with each copy of the object code that the
   Library is used in it and that the Library and its use are
   covered by this License.

   b) Accompany the object code with a copy of the GNU GPL and this license
   document.

  4. Combined Works.

  You may convey a Combined Work under terms of your choice that,
taken together, effectively do not restrict modification of the
portions of the Library contained in the Combined Work and reverse
engineering for debugging such modifications, if you also do each of
the following:

   a) Give prominent notice with each copy of the Combined Work that
   the Library is used in it and that the Library and its use are
   covered by this License.

   b) Accompany the Combined Work with a copy of the GNU GPL and this license
   document.

   c) For a Combined Work that displays copyright notices during
   execution, include the copyright notice for the Library among
   these notices, as well as a reference directing the user to the
   copies of the GNU GPL and this license document.

   d) Do one of the following:

       0) Convey the Minimal Corresponding Source under the terms of this
       License, and the Corresponding Application Code in a form
       suitable for, and under terms that permit, the user to
       recombine or relink the Application with a modified version of
       the Linked Version to produce a modified Combined Work, in the
       manner specified by section 6 of the GNU GPL for conveying
       Corresponding Source.

       1) Use a suitable shared library mechanism for linking with the
       Library.  A suitable mechanism is one that (a) uses at run time
       a copy of the Library already present on the user's computer
       system, and (b) will operate properly with a modified version
       of the Library that is interface-compatible with the Linked
       Version.

   e) Provide Installation Information, but only if you would otherwise
   be required to provide such information under section 6 of the
   GNU GPL, and only to the extent that such information is
   necessary to install and execute a modified version of the
   Combined Work produced by recombining or relinking the
   Application with a modified version of the Linked Version. (If
   you use option 4d0, the Installation Information must accompany
   the Minimal Corresponding Source and Corresponding Application
   Code. If you use option 4d1, you must provide the Installation
   Information in the manner specified by section 6 of the GNU GPL
   for conveying Corresponding Source.)

  5. Combined Libraries.

  You may place library facilities that are a work based on the
Library side by side in a single library together with other library
facilities that are not Applications and are not covered by this
License, and convey such a combined library under terms of your
choice, if you do both of the following:

   a) Accompany the combined library with a copy of the same work based
   on the Library, uncombined with any other library facilities,
   conveyed under the terms of this License.

   b) Give prominent notice with the combined library that part of it
   is a work based on the Library, and explaining where to find the
   accompanying uncombined form of the same work.

  6. Revised Versions of the GNU Lesser General Public License.

  The Free Software Foundation may publish revised and/or new versions
of the GNU Lesser General Public License from time to time. Such new
versions will be similar in spirit to the present version, but may
differ in detail to address new problems or concerns.

  Each version is given a distinguishing version number. If the
Library as you received it specifies that a certain numbered version
of the GNU Lesser General Public License "or any later version"
applies to it, you have the option of following the terms and
conditions either of that published version or of any later version
published by the Free Software Foundation. If the Library as you
received it does not specify a version number of the GNU Lesser
General Public License, you may choose any version of the GNU Lesser
General Public License ever published by the Free Software Foundation.

  If the Library as you received it specifies that a proxy can decide
whether future versions of the GNU Lesser General Public License shall
apply, that proxy's public statement of acceptance of any version is
permanent authorization for you to choose that version for the
Library.

"""

let licenseLGPLHeader = """
// This is free software: you can redistribute and/or modify it
// under the terms of the GNU Lesser General Public License 3.0
// as published by the Free Software Foundation https://fsf.org


"""
