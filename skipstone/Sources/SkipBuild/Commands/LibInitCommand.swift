import Foundation
import ArgumentParser
import SkipSyntax
import TSCBasic
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
struct LibInitCommand: MessageCommand, CreateOptionsCommand, ToolOptionsCommand, BuildOptionsCommand, StreamingCommand {
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

    /// Attempts to parse module names like "skiptools/skip-ui/SkipUI" into a full repo and path
    var modules: [PackageModule] {
        get throws {
            try self.moduleNames.map {
                try PackageModule(parse: $0)
            }
        }
    }

    func performCommand(with out: MessageQueue) async throws {
        await out.yield(MessageBlock(status: nil, "Initializing Skip library \(self.projectName)"))

        let dir = self.createOptions.dir ?? "."

        let createdURL = try await buildSkipProject(projectName: self.projectName, modules: self.modules, resourceFolder: createOptions.resourcePath, dir: dir, configuration: createOptions.configuration, build: buildOptions.build, test: buildOptions.test, tree: self.createOptions.tree, chain: createOptions.chain, appid: self.appid, version: self.version, apk: apk, ipa: ipa, with: out)

        await out.yield(MessageBlock(status: .pass, "Created module \(moduleNames.joined(separator: ", ")) in \(createdURL.path)"))
    }
}

extension ToolOptionsCommand {
    func buildSkipProject(projectName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: String, configuration: String, build: Bool, test: Bool, tree: Bool, chain: Bool, appid: String?, version: String?, apk: Bool, ipa: Bool, with out: MessageQueue) async throws -> URL {
        let projectURL = try await initSkipLibrary(projectName: projectName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, chain: chain, app: appid != nil, with: out)

        let projectPath = try projectURL.absolutePath
        let primaryModuleName = modules.first?.moduleName ?? "Module"

        if let appid = appid {
            let appModuleName = primaryModuleName
            let primaryModuleAppTarget = appModuleName + "App"

            let sourcesFolderName = "Sources"

            let primaryModuleAppSourcesPath = sourcesFolderName + "/" + primaryModuleAppTarget
            let appMainSwiftFileName = primaryModuleAppTarget + "Main.swift"
            let primaryModuleAppMainPath = primaryModuleAppSourcesPath + "/" + appMainSwiftFileName
            // Sources/PlaygroundApp/PlaygroundAppMain.swift
            let appMainContents = """
            import SwiftUI
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
            import Foundation
            import OSLog
            import SwiftUI

            let logger: Logger = Logger(subsystem: "\(appid)", category: "\(primaryModuleName)")

            /// The Android SDK number we are running against, or `nil` if not running on Android
            let androidSDK = ProcessInfo.processInfo.environment["android.os.Build.VERSION.SDK_INT"].flatMap({ Int($0) })

            #if !SKIP
            public protocol \(primaryModuleAppTarget) : App {
            }

            /// The entry point to the app, which simply loads the `ContentView` from the `AppUI` module.
            public extension \(primaryModuleAppTarget) {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }

            #else
            import android.Manifest
            import android.app.Application
            import androidx.activity.compose.setContent
            import androidx.appcompat.app.AppCompatActivity
            import androidx.compose.foundation.isSystemInDarkTheme
            import androidx.compose.material3.ExperimentalMaterial3Api
            import androidx.compose.material3.MaterialTheme
            import androidx.compose.material3.darkColorScheme
            import androidx.compose.material3.dynamicDarkColorScheme
            import androidx.compose.material3.dynamicLightColorScheme
            import androidx.compose.material3.lightColorScheme
            import androidx.compose.runtime.saveable.rememberSaveableStateHolder
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
            @ExperimentalMaterial3Api
            public class MainActivity : AppCompatActivity {
                public init() {
                }

                public override func onCreate(savedInstanceState: android.os.Bundle?) {
                    super.onCreate(savedInstanceState)

                    setContent {
                        let saveableStateHolder = rememberSaveableStateHolder()
                        saveableStateHolder.SaveableStateProvider(true) {
                            MaterialThemedContentView()
                        }
                    }

                    let permissions = listOf(
                        Manifest.permission.ACCESS_COARSE_LOCATION,
                        Manifest.permission.ACCESS_FINE_LOCATION
                        //Manifest.permission.CAMERA,
                        //Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    )

                    let requestTag = 1 // TODO: handle with onRequestPermissionsResult
                    ActivityCompat.requestPermissions(self, permissions.toTypedArray(), requestTag)
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
                    logger.info("onRequestPermissionsResult: \\(requestCode)")
                }
            }

            @ExperimentalMaterial3Api
            @Composable func MaterialThemedContentView() {
                let context = LocalContext.current
                let darkMode = isSystemInDarkTheme()
                // Dynamic color is available on Android 12+
                let dynamicColor = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S

                let colorScheme = dynamicColor
                    ? (darkMode ? dynamicDarkColorScheme(context) : dynamicLightColorScheme(context))
                    : (darkMode ? darkColorScheme() : lightColorScheme())

                MaterialTheme(colorScheme: colorScheme) {
                    ContentView().Compose()
                }
            }

            #endif

            """

            let primaryModuleSources = sourcesFolderName + "/" + primaryModuleName

            let appModuleApplicationStubFileBase = primaryModuleAppTarget + ".swift"
            let appModuleApplicationStubFilePath = primaryModuleSources + "/" + appModuleApplicationStubFileBase

            let appModuleApplicationStubFileURL = projectURL.appending(path: appModuleApplicationStubFilePath)
            try FileManager.default.createDirectory(at: appModuleApplicationStubFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try appExtContents.write(to: appModuleApplicationStubFileURL, atomically: true, encoding: .utf8)


            // Sources/Playground/PlaygroundApp.swift
            let contentViewContents = """
            import SwiftUI
            import OSLog

            struct ContentView: View {
                var body: some View {
                    VStack {
                        Image(systemName: "heart")
                            .foregroundStyle(.red)
                        Text("Hello, Skip!")
                            .font(.largeTitle)
                    }
                    .padding()
                }
            }

            """

            let contentViewFileBase = "ContentView.swift"
            let contentViewRelativePath = primaryModuleSources + "/" + contentViewFileBase

            let contentViewURL = projectURL.appending(path: contentViewRelativePath)
            try FileManager.default.createDirectory(at: contentViewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contentViewContents.write(to: contentViewURL, atomically: true, encoding: .utf8)

            // create a top-level ModuleName.xcconfig
            let configContents = """
            // The configuration file for your Skip App (https://skip.tools)

            // PRODUCT_NAME is the default title of the app
            PRODUCT_NAME = \(appModuleName)

            // PRODUCT_BUNDLE_IDENTIFIER is the unique id for both the iOS and Android app
            PRODUCT_BUNDLE_IDENTIFIER = \(appid)

            // The user-visible name of the app (localizable)
            //INFOPLIST_KEY_CFBundleDisplayName = App Name
            //INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.utilities

            // The semantic version for the app matching the git tag for the release
            MARKETING_VERSION = \(version ?? "0.0.1")

            // The build number specifying the internal app version
            CURRENT_PROJECT_VERSION = 1

            IPHONEOS_DEPLOYMENT_TARGET = 16.0
            MACOSX_DEPLOYMENT_TARGET = 13.0

            // On-device testing may need to override the bundle ID
            // PRODUCT_BUNDLE_IDENTIFIER[config=Debug][sdk=iphoneos*] = \(appid)

            // Assemble the APK as part of the build process
            SKIP_BUILD_APK = YES

            // Building the target will lauch the app for iphone* targets
            SKIP_LAUNCH_APK[sdk=iphone*] = YES

            // iOS-specific Info.plist property keys
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*] = YES
            INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*] = YES
            INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*] = YES
            INFOPLIST_KEY_UIStatusBarStyle[sdk=iphone*] = UIStatusBarStyleDefault
            INFOPLIST_KEY_UISupportedInterfaceOrientations[sdk=iphone*] = UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown

            // Development team ID for on-device testing
            //DEVELOPMENT_TEAM =
            //CODE_SIGNING_IDENTITY = -
            //CODE_SIGNING_REQUIRED = NO
            """

            let xcconfigURL = projectURL.appending(path: primaryModuleName + ".xcconfig")
            try configContents.write(to: xcconfigURL, atomically: true, encoding: .utf8)
            let xcconfigFileName = xcconfigURL.lastPathComponent


            // the Sources/MODULE_NAMEApp/ folder for iOS metadata
            let appModule_Sources_Path = sourcesFolderName + "/" + primaryModuleAppTarget

            let Assets_xcassets_name = "Assets.xcassets"
            let Assets_xcassets_path = appModule_Sources_Path + "/" + Assets_xcassets_name
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
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "16x16"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "16x16"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "32x32"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "32x32"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "128x128"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "128x128"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "256x256"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "256x256"
                },
                {
                  "idiom" : "mac",
                  "scale" : "1x",
                  "size" : "512x512"
                },
                {
                  "idiom" : "mac",
                  "scale" : "2x",
                  "size" : "512x512"
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


            let skipBuildAPKScript = """
            if [ \\"${SKIP_BUILD_APK}\\" != \\"YES\\" ]; then\\n  echo \\"note: Not building apk due to SKIP_BUILD_APK setting\\"\\n  exit 0\\nfi\\n\\nPLUGIN=${BUILD_ROOT}/../../SourcePackages/artifacts/skip/skip/skip.artifactbundle/macos\\nPATH=${BUILD_ROOT}/Debug:${PLUGIN}:${PATH}:${HOMEBREW_PREFIX:-/opt/homebrew}/bin\\nPROJECT=$(basename ${PROJECT_DIR})\\nSRCPKG=${BUILD_ROOT}/../../SourcePackages\\necho \\"note: Building APK for: ${PROJECT}\\"\\nexport ANDROID_HOME=${ANDROID_HOME:-${HOME}/Library/Android/sdk}\\nwhich skip\\nmkdir -p Skip/build/artifacts/\\nskip gradle --package \\"${PROJECT}\\" --module ${PROJECT_NAME}UI assemble${CONFIGURATION}\\ncd Skip/build/\\nln -sfh ${SRCPKG}/plugins/*.output .\\ncd artifacts/\\n#ln -f ${SRCPKG}/plugins/*.output/*/skipstone/*/build/outputs/apk/*/*.apk .\\nln -f ${SRCPKG}/plugins/*.output/*/skipstone/*/.build/*/outputs/apk/*/*.apk .\\n\\n# this is the expected output file, so ensure that it exists\\nls -lah ${SRCROOT}/Skip/build/artifacts/${PROJECT_NAME}UI-${CONFIGURATION}.apk\\n
            """

            let skipLaunchAPKScript = """
            if [ \\"${SKIP_LAUNCH_APK}\\" != \\"YES\\" ]; then\\n  echo \\"note: Not launching apk due to SKIP_LAUNCH_APK setting\\"\\n  exit 0\\nfi\\n\\nPLUGIN=${BUILD_ROOT}/../../SourcePackages/artifacts/skip/skip/skip.artifactbundle/macos\\nPATH=${BUILD_ROOT}/Debug:${PLUGIN}:${PATH}:${HOMEBREW_PREFIX:-/opt/homebrew}/bin\\necho \\"note: Running skip adb install\\"\\nskip adb install -t -r -d -g Skip/build/artifacts/${PROJECT_NAME}UI-${CONFIGURATION}.apk\\necho \\"note: Running skip adb am start-activity\\"\\nskip adb shell am start-activity -S -W -n ${PRODUCT_BUNDLE_IDENTIFIER}/.MainActivity\\n
            """

            let xcodeProjectContents = """
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
		49F90C312A52156300F06D93 /* App.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; name = App.entitlements; path = Sources/App/App.entitlements; sourceTree = "<group>"; };
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
				49F90C312A52156300F06D93 /* App.entitlements */,
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
			buildConfigurationList = 49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(primaryModuleAppTarget)" */;
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
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
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
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Sources/App/App.entitlements;
				CODE_SIGN_STYLE = Automatic;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
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
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Sources/App/App.entitlements;
				CODE_SIGN_STYLE = Automatic;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
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
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Sources/App/App.entitlements;
				CODE_SIGN_STYLE = Automatic;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
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
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
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
		49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(primaryModuleAppTarget)" */ = {
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

            let xcodeProjectFolder = try projectURL.append(path: primaryModuleName + ".xcodeproj", create: true)
            let xcodeProjectPbxprojURL = xcodeProjectFolder.appending(path: "project.pbxproj")
            // change spaces to tabs in the pbxproj, since that is what Xcode will do when it saves it
            try xcodeProjectContents.replacingOccurrences(of: "    ", with: "\t").write(to: xcodeProjectPbxprojURL, atomically: true, encoding: .utf8)

            if ipa == true {
                // xcodebuild -derivedDataPath .build/DerivedData -skipPackagePluginValidation -archivePath "${ARCHIVE_PATH}" -configuration "${CONFIGURATION}" -scheme "${SKIP_MODULE}" -sdk "iphoneos" -destination "generic/platform=iOS" -jobs 1 archive CODE_SIGNING_ALLOWED=NO
                let archiveBasePath = ".build/Skip/artifacts/" + configuration.capitalized

                let archivePath = archiveBasePath + "/" + primaryModuleAppTarget + ".xcarchive"
                let ipaPath = archiveBasePath + "/" + primaryModuleAppTarget + ".ipa"
                let ipaURL = projectURL.appending(path: ipaPath)

                // note that derivedDataPath and archivePath are relative to CWD rather than
                let fullArchivePath = projectURL.path + "/" + archivePath
                let fullDerivedDataPath = projectURL.path + "/.build/DerivedData"

                await run(with: out, "Archiving iOS ipa", [
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
                    "SKIP_BUILD_APK=NO",
                    "SKIP_LAUNCH_APK=NO",
                    "ZERO_AR_DATE=1",
                ])

                let archiveAppPath = archivePath + "/Products/Applications/" + primaryModuleAppTarget + ".app"
                let archiveAppURL = projectURL.appending(path: archiveAppPath)

                // TODO: eventually we will want to create the .ipa by the exportArchive mechanism, but that requires code signing and some means to specify the certificates in the tool…
                // xcodebuild -exportArchive -archivePath /Path/To/Output/YourApp.xcarchive -exportPath /Path/To/ipa/Output/Folder -exportOptionsPlist /Path/To/ExportOptions.plist

                // …so now, just run ditto to create the app zip

                // need to first copy the contents over to a "Payload" folder, since the root of the .ipa needs to be "Payload"
                let archiveAppPayloadURL = archiveAppURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("Payload", isDirectory: true)
                try FileManager.default.createDirectory(at: archiveAppPayloadURL, withIntermediateDirectories: false)
                let archiveAppContentsURL = archiveAppPayloadURL
                    .appendingPathComponent(archiveAppURL.lastPathComponent, isDirectory: true)

                try FileManager.default.copyItem(at: archiveAppURL, to: archiveAppContentsURL)
                try FileManager.default.zeroFileTimes(under: archiveAppPayloadURL)

                // ditto -c -k --sequesterRsrc /path/to/source /path/to/destination/archive.zip
                // ditto does not create reproducible files
                // await run(with: out, "Assembing \(ipaURL.lastPathComponent)", ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", archiveAppPayloadURL.path, ipaURL.path])

                await run(with: out, "Assemble \(ipaURL.lastPathComponent)", ["zip", "-9", "-r", ipaURL.path, archiveAppPayloadURL.lastPathComponent], in: archiveAppPayloadURL.deletingLastPathComponent())

                await checkFile(ipaURL, with: out, title: "Verify \(ipaURL.lastPathComponent)") { url in
                    try "Verify \(ipaURL.lastPathComponent) \(ByteCountFormatter.string(fromByteCount: Int64(url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), countStyle: .file))"
                }

                await checkFile(ipaURL, with: out, title: "Checksum Archive") { url in
                    try "IPA SHA256: \(url.SHA256Hash())"
                }
            }
        }

        if tree {
            await showFileTree(in: projectPath, with: out)
        }

        if build == true || apk == true {
            await run(with: out, "Resolving dependencies", ["swift", "package", "resolve", "-v", "--package-path", projectURL.path])

            // we need to build regardless of preference in order to build the apk
            await run(with: out, "Building \(projectName)", ["swift", "build", "-v", "-c", configuration, "--package-path", projectURL.path])

            if apk == true { // assemble the .apk
                let env = ProcessInfo.processInfo.environment

                let gradleProjectDir = projectURL.path + "/.build/plugins/outputs/" + projectName + "/" + primaryModuleName + "/skipstone"
                let relativeBuildDir = ".build/" + projectName

                let action = "assemble" + configuration.capitalized // turn "debug" into "Debug" and "release" into "Release"
                await run(with: out, "Assembling Android apk", ["gradle", action, "--console=plain", "--info", "--project-dir", gradleProjectDir, "-PbuildDir=" + relativeBuildDir], environment: env)
                //{ result in (result, nil) }

                // the expected path for the gradle output folder of the assemble action
                let outputsPath = gradleProjectDir + "/" + primaryModuleName  + "/" + relativeBuildDir + "/outputs"

                // for example: skipapp-playground/.build/plugins/outputs/skipapp-playground/Playground/skipstone/Playground/.build/skipapp-playground/outputs/apk/release/Playground-release.apk
                let apkPath = outputsPath + "/apk/" + configuration + "/" + primaryModuleName + "-" + configuration + ".apk"
                let apkURL = URL(fileURLWithPath: apkPath, isDirectory: false)

                await checkFile(apkURL, with: out, title: "Verify \(apkURL.lastPathComponent)") { url in
                    try "Verify \(apkURL.lastPathComponent) \(ByteCountFormatter.string(fromByteCount: Int64(url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0), countStyle: .file))"
                }

                await checkFile(apkURL, with: out, title: "Checksum Archive") { url in
                    try "APK SHA256: \(url.SHA256Hash())"
                }

            }
        }

        if test == true {
            try await runSkipTests(in: projectURL, configuration: configuration, swift: true, kotlin: true, with: out)
        }

        return projectURL
    }

    func initSkipLibrary(projectName: String, modules: [PackageModule], resourceFolder: String?, dir outputFolder: String, chain: Bool, app: Bool, with out: MessageQueue) async throws -> URL {
        var isDir: Foundation.ObjCBool = false
        if !FileManager.default.fileExists(atPath: outputFolder, isDirectory: &isDir) {
            throw InitError(errorDescription: "Specified output folder does not exist: \(outputFolder)")
        }
        if isDir.boolValue == false {
            throw InitError(errorDescription: "Specified output folder is not a directory: \(outputFolder)")
        }

        let projectFolder = outputFolder + "/" + projectName
        if FileManager.default.fileExists(atPath: projectFolder) {
            throw InitError(errorDescription: "Specified project path already exists: \(projectFolder)")
        }

        let projectFolderURL = URL(fileURLWithPath: projectFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        let packageURL = projectFolderURL.appending(path: "Package.swift")

        let sourcesURL = try projectFolderURL.append(path: "Sources", create: true)
        let testsURL = try projectFolderURL.append(path: "Tests", create: true)

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
        var packageDependencies: [String] = [
            ".package(url: \"https://source.skip.tools/skip.git\", from: \"\(skipPackageVersion)\")"
        ]

        for i in modules.indices {
            let module = modules[i]
            let moduleName = module.moduleName

            // the isAppModule is the initial module in the list when we specify we want to create an app module
            let isAppModule = app && i == modules.startIndex ? true : false

            // the subsequent module
            let nextModule = i < modules.endIndex - 1 ? modules[i+1] : nil
            let nextModuleName = nextModule?.moduleName

            //let moduleKtName = moduleName + "Kt"

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
                - block: 'plugins'
                  contents:
                    - 'id("com.android.application") version "8.1.0"'
                  remove:
                    - 'id("com.android.library") version "8.1.0"'
                - block: 'android'
                  contents:
                    - 'namespace = System.getenv("PRODUCT_BUNDLE_IDENTIFIER") ?: "app.ui"'
                    - block: 'defaultConfig'
                      contents:
                        # Android app config and AndroidManifest.xml metadata can be specified here
                        # - 'applicationId = System.getenv("PRODUCT_BUNDLE_IDENTIFIER") ?: "app.ui"'
                    - block: 'buildFeatures'
                      contents:
                        - 'buildConfig = true'
                    - block: 'buildTypes'
                      contents:
                        - block: 'release'
                          contents:
                            # by default we sign with the debug key; for publishing to an app store, the developer key will need to be supplied
                            - 'signingConfig = signingConfigs.getByName("debug")'
                            # enabling minification reduces compose dependency classe size ~85%
                            - 'isMinifyEnabled = true'
                            - 'proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")'
            """

            try (isAppModule ? skipYamlApp : skipYamlGeneric).write(to: sourceSkipYamlFile, atomically: true, encoding: .utf8)

            let sourceSwiftFile = sourceDir.appending(path: "\(moduleName).swift")
            try """
            public class \(moduleName)Module {
            }

            """.write(to: sourceSwiftFile, atomically: true, encoding: .utf8)

            let testDir = try testsURL.append(path: moduleName + "Tests", create: true)

            let testSkipDir = try testDir.append(path: "Skip", create: true)

            let testSwiftFile = testDir.appending(path: "\(moduleName)Tests.swift")

            try """
            import XCTest
            import OSLog
            import Foundation

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
            #if os(macOS) // Skip transpiled tests only run on macOS targets
            import SkipTest

            /// This test case will run the transpiled tests for the Skip module.
            @available(macOS 13, *)
            final class XCSkipTests: XCTestCase, XCGradleHarness {
                public func testSkipModule() async throws {
                    try await runGradleTests(device: .none) // set device ID to run in Android emulator vs. robolectric
                }
            }
            #endif
            """.write(to: testSkipModuleFile, atomically: true, encoding: .utf8)

            // app tests won't build if this is in place
            let skipYamlAppTests = """
            # Configuration file for https://skip.tools project
            build:
              contents:
                - block: 'plugins'
                  remove:
                    - 'id("com.android.library") version "8.1.0"'
            """


            let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
            try (isAppModule ? skipYamlAppTests : skipYamlGeneric).write(to: testSkipYamlFile, atomically: true, encoding: .utf8)

            products += """
                    .library(name: "\(moduleName)", type: .dynamic, targets: ["\(moduleName)"]),

            """

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

                let testResourcesDir = try testDir.append(path: resourceFolder, create: true)
                let testResourcesFile = testResourcesDir.appending(path: "TestData.json")
                try """
                {
                  "testModuleName": "\(moduleName)"
                }
                """.write(to: testResourcesFile, atomically: true, encoding: .utf8)

                resourcesAttribute = ", resources: [.process(\"\(resourceFolder)\")]"
            }

            if isAppModule {
                let androidManifestContents = """
                <?xml version="1.0" encoding="utf-8"?>
                <manifest xmlns:android="http://schemas.android.com/apk/res/android">
                    <!-- example permissions for using device location -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/> -->
                    <!-- <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/> -->

                    <!-- permissions needed for using the internet or an embedded WebKit browser -->
                    <uses-permission android:name="android.permission.INTERNET" />
                    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
                    <meta-data android:name="android.webkit.WebView.EnableSafeBrowsing" android:value="false" />

                    <application
                        android:label="${PRODUCT_NAME}"
                        android:name="${PRODUCT_BUNDLE_IDENTIFIER}.AndroidAppMain"
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

            for modDep in module.dependencies {
                if let repoName = modDep.repositoryName {
                    let depVersion = modDep.repositoryVersion ?? "0.0.0"
                    let packDep = ".package(url: \"https://source.skip.tools/\(repoName).git\", from: \"\(depVersion)\")"
                    if !packageDependencies.contains(packDep) {
                        packageDependencies.append(packDep)
                    }
                    moduleDeps.append(".product(name: \"\(modDep.moduleName)\", package: \"\(repoName)\")")

                }
            }

            let moduleDep = moduleDeps.joined(separator: ", ")

            targets += """
                    .target(name: "\(moduleName)", dependencies: [\(moduleDep)]\(resourcesAttribute), plugins: [.plugin(name: "skipstone", package: "skip")]),
                    .testTarget(name: "\(moduleName)Tests", dependencies: ["\(moduleName)", .product(name: "SkipTest", package: "skip")]\(resourcesAttribute), plugins: [.plugin(name: "skipstone", package: "skip")]),

            """
        }

        products += """
            ]
        """
        targets += """
            ]
        """

        let dependencies = "    dependencies: [\n        " + packageDependencies.joined(separator: ",\n        ") + "\n]"

        let packageSource = """
        // swift-tools-version: 5.9
        // This is a [Skip](https://skip.tools) package,
        // containing Swift "ModuleName" library targets
        // that will use the Skip plugin to transpile the
        // Swift Package, Sources, and Tests into an
        // Android Gradle Project with Kotlin sources and JUnit tests.
        import PackageDescription

        let package = Package(
            name: "\(projectName)",
            defaultLocalization: "en",
            platforms: [.iOS(.v16), .macOS(.v13), .tvOS(.v16), .watchOS(.v9), .macCatalyst(.v16)],
        \(products),
        \(dependencies),
        \(targets)
        )
        """

        try packageSource.write(to: packageURL, atomically: true, encoding: .utf8)


        let readmeURL = projectFolderURL.appending(path: "README.md")

        try """
        # \(projectName)

        This is a [Skip](https://skip.tools) Swift/Kotlin library project containing the following modules:

        \(modules.map(\.moduleName).joined(separator: "\n"))

        """.write(to: readmeURL, atomically: true, encoding: .utf8)

        //        let packageJSONString = try await outputOptions.exec("Checking project \(projectName)", [toolOptions.swift, "package", "dump-package", "--package-path", projectFolderURL.path], resultHandler: { result in
        //            guard let stdout = try result?.get().out else { return nil }
        //            return try JSONDecoder().decode(PackageManifest.self, from: Data(stdout.utf8))
        //        })

        let packageJSONString = try await run(with: out, "Checking project \(projectName)", ["swift", "package", "dump-package", "--package-path", projectFolderURL.path]).get().stdout

        let packageJSON = try JSONDecoder().decode(PackageManifest.self, from: Data(packageJSONString.utf8))
        _ = packageJSON

        return projectFolderURL
    }
}

extension ToolOptionsCommand {

    /// Perform a monitor check on the given URL
    func checkFile(_ url: URL, with out: MessageQueue, title: String, handle: @escaping (URL) throws -> String) async {
        await outputOptions.monitor(with: out, title, resultHandler: { result in
            do {
                if let resultURL = try result?.get() {
                    let message = try handle(resultURL)
                    return (result, MessageBlock(status: result?.messageStatusAny, message))
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

struct PackageModule {
    var moduleName: String
    var organizationName: String? = nil
    var repositoryName: String? = nil
    var repositoryVersion: String? = nil
    var dependencies: [PackageModule] = []

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

extension URL {
    /// Create the child directory of the given parent
    func append(path: String, create directory: Bool = false) throws -> URL {
        let path = appendingPathComponent(path, isDirectory: directory)
        if directory {
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: false)
        }
        return path
    }
}
