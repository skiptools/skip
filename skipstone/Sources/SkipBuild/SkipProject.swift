// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import SkipSyntax

struct MissingProjectFileError : LocalizedError {
    var errorDescription: String?
}

struct AppVerifyError : LocalizedError {
    var errorDescription: String?
}

enum ModuleMode {
    case transpiled
    case transpiledBridged
    case native
    case nativeBridged
    case kotlincompat

    var isNative: Bool {
        switch self {
        case .transpiled: return false
        case .transpiledBridged: return false
        case .native: return true
        case .nativeBridged: return true
        case .kotlincompat: return true
        }
    }

    var isBridged: Bool {
        switch self {
        case .transpiled: return false
        case .transpiledBridged: return true
        case .native: return false
        case .nativeBridged: return true
        case .kotlincompat: return true
        }
    }

}

struct ProjectOptionValues {
    var projectName: String
    var swiftPackageVersion: String
    var iOSMinVersion: Double
    var macOSMinVersion: Double?
    var chain: Bool
    var gitRepo: Bool
    var appfair: Bool
    var free: Bool
    var zero: Bool
    var github: Bool
    var fastlane: Bool
    
    /// Prior to iOS 26, the default macOS version is 3 below the iOS version in terms of API compatibility (i.e., iOS 18.0 == macOS 15.0)
    var macOSMinVersionCalculated: Double {
        macOSMinVersion ?? (iOSMinVersion < 26.0 ? iOSMinVersion - 3.0 : iOSMinVersion)
    }

}

func isValidProjectName(_ name: String) -> String? {
    let invalidDesc = "Project name must contain only lower-case letters or a dash"

    // Ensure the name is not empty
    guard !name.isEmpty else { return invalidDesc }

    if name.count < 2 { return invalidDesc }

    // Ensure the first character is an uppercase letter
    if name != name.lowercased() { return invalidDesc }

    // Define a character set with valid characters (letters, numbers)
    let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))

    // Check if the name contains only valid characters
    if !name.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) {
        return invalidDesc
    }

    return nil
}

func isValidModuleName(_ name: String) -> String? {
    let invalidDesc = "ModuleName must be capitalized and contain only letters or numbers"

    // Ensure the name is not empty
    guard !name.isEmpty else { return invalidDesc }

    if name.count < 2 { return invalidDesc }

    // Ensure the first character is an uppercase letter
    guard let firstChar = name.first, firstChar.isUppercase else { return invalidDesc }

    // Define a character set with valid characters (letters, numbers)
    let validCharacters = CharacterSet.alphanumerics

    // Check if the name contains only valid characters
    if !name.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) {
        return invalidDesc
    }

    return nil
}

func isValidBundleIdentifier(_ identifier: String) -> String? {
    let invalidDesc = "The bundle identifier must be a dot-separated series of lowercase letters or numbers"

    // Ensure the identifier is not empty
    guard !identifier.isEmpty else { return invalidDesc }

    // Ensure the identifier does not start or end with a period
    guard !identifier.hasPrefix(".") && !identifier.hasSuffix(".") else { return invalidDesc }

    // Ensure it does not contain consecutive periods
    guard !identifier.contains("..") else { return invalidDesc }

    // Define valid characters: letters, numbers, dash, and periods
    let validCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))

    // Check if all characters are valid
    guard identifier.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else { return invalidDesc }

    // Ensure it has at least two segments
    let components = identifier.split(separator: ".")
    guard components.count > 1 else { return invalidDesc }

    return nil
}

class FrameworkProjectLayout {
    var packageSwift: URL

    init(root: URL, check: (URL, Bool) throws -> () = checkURLExists) rethrows {
        self.packageSwift = try root.resolve("Package.swift", check: check)
    }

    /// A check that passes every time
    static func noURLChecks(url: URL, isDirectory: Bool) {
    }

    /// A check that verifies that the file URL exists
    static func checkURLExists(url: URL, isDirectory: Bool) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            throw MissingProjectFileError(errorDescription: "Expected path at \(url.path) does not exist")
        }
        if isDir.boolValue != isDirectory {
            throw MissingProjectFileError(errorDescription: "Expected path at \(url.path) should be a \(isDirectory ? "directory" : "file")")
        }
    }

    /// Get the default Java package name for the given module, throwing an error if the Java package name contains a reserved keyword.
    static func packageName(forModule moduleName: String) throws -> String {
        // https://docs.oracle.com/javase/tutorial/java/nutsandbolts/_keywords.html
        let keywords: Set<String> = ["abstract", "continue", "for", "new", "switch", "assert", "default", "goto", "package", "synchronized", "boolean", "do", "if", "private", "this", "break", "double", "implements", "protected", "throw", "byte", "else", "import", "public", "throws", "case", "enum", "instanceof", "return", "transient", "catch", "extends", "int", "short", "try", "char", "final", "interface", "static", "void", "class", "finally", "long", "strictfp", "volatile", "const", "float", "native", "super", "while"]

        let pname = KotlinTranslator.packageName(forModule: moduleName)
        let packageParts = pname.split(separator: ".")
        for part in packageParts {
            if keywords.contains(String(part)) {
                throw InitError(errorDescription: "The module name \"\(moduleName)\" is invalid because the derived Java package name \"\(pname)\" contains a reserved keyword: \"\(part)\"")
            }
        }
        return pname
    }

    static func createSkipLibrary(options: ProjectOptionValues, productName: String?, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, app: Bool, nativeMode: NativeMode, moduleMode: ModuleMode, moduleTests createModuleTests: Bool, packageResolved packageResolvedURL: URL?) throws -> URL {
        let projectName = options.projectName
        if modules.isEmpty {
            throw InitError(errorDescription: "Must specify at least one module name")
        }

        let validModuleCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        for module in modules {
            if module.moduleName.rangeOfCharacter(from: validModuleCharacters.inverted) != nil {
                throw InitError(errorDescription: "Module name contains an invalid character (must be alphanumeric): \(module.moduleName)")
            }
        }

        let projectFolderURL = outputFolder // .appendingPathComponent(projectName, isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolderURL, withIntermediateDirectories: true)

        let sourcesURL = try projectFolderURL.append(path: "Sources", create: true)

        let license = options.defaultLicense(app: app)
        var sourceHeader = license?.sourceHeader.appending("\n\n") ?? ""
        let testSourceHeader = sourceHeader
        var sourceFooter = ""
        if moduleMode == .transpiledBridged {
            // bridged code needs to be wrapped in a check for SKIP_BRIDGE
            sourceHeader += "#if !SKIP_BRIDGE\n"
            sourceFooter += "\n#endif\n"
        }

        // the part of a target parameter that will only include skip when zero is not set
        let skipPluginArray = #"[.plugin(name: "skipstone", package: "skip")]"#

        var products = """
            products: [

        """

        var targets = """
            targets: [

        """


#if DEBUG
        let skipPackageVersion = "1.0.0"
#else
        let skipPackageVersion = skipVersion
#endif
        var packageHeader = """
        // swift-tools-version: \(options.swiftPackageVersion)

        """

        packageHeader += """
        // This is a Skip (https://skip.dev) package.
        import PackageDescription

        """

        var packageDependencies: [String] = [
            ".package(url: \"https://source.skip.tools/skip.git\", from: \"\(skipPackageVersion)\")"
        ]

        for moduleIndex in modules.indices {
            let module = modules[moduleIndex]
            let moduleName = module.moduleName
            let modulePackage = try packageName(forModule: moduleName)
            // the isAppModule is the initial module in the list when we specify we want to create an app module
            let isAppModule = app == true && moduleIndex == modules.startIndex
            // the model module is the second in the chain
            let isModelModule = app == true && moduleIndex == modules.startIndex + 1
            // a native module is either the second module for an app project, or any module for a non-app --native project
            let native = moduleMode.isNative
            let isNativeAppModule = isAppModule && nativeMode.contains(.nativeApp)
            let isNativeModule = native && (isModelModule || !app || isNativeAppModule)
            // we output the model when it is the second module, or when there is only a single top-level app module
            let shouldOutputModel = isModelModule || (app == true && modules.count == 1)
            // this is the final module in the chain, which will add a dependency on SkipFoundation
            let isFinalModule = moduleIndex == modules.endIndex - 1

            // the subsequent module
            let nextModule = moduleIndex < modules.endIndex - 1 ? modules[moduleIndex+1] : nil
            let nextModuleName = nextModule?.moduleName

            let sourceDir = try sourcesURL.append(path: moduleName, create: true)

            // modules that are dependent on the native module do not run the skipstone plugin or have resources
            let isDependentNativeModule = native && moduleIndex > 1

            if isNativeAppModule || !isDependentNativeModule {
                let sourceSkipDir = try sourceDir.append(path: "Skip", create: true)

                let sourceSkipYamlFile = sourceSkipDir.appending(path: "skip.yml")

                let skipYamlGeneric = """
                # Skip configuration for \(moduleName) module
                #
                # Kotlin dependencies and Gradle build options for this module can be configured here
                #build:
                #  contents:
                #    - block: 'dependencies'
                #      contents:
                #        - 'implementation("androidx.compose.runtime:runtime")'

                """

                var skipYamlModule = skipYamlGeneric
                if isNativeModule && !(isAppModule && !isNativeAppModule) {
                    skipYamlModule += """

                    # this is a natively-compiled Skip Fuse module
                    skip:
                      mode: 'native'

                    """

                    if moduleMode == .kotlincompat {
                        skipYamlModule += """
                          bridging:
                            enabled: true
                            options: 'kotlincompat'

                        """
                    } else if moduleMode == .nativeBridged {
                        skipYamlModule += """
                          bridging: true

                        """
                    }
                } else {
                    skipYamlModule += """

                    # this is a transpiled Skip Lite module
                    skip:
                      mode: 'transpiled'

                    """

                    if moduleMode == .transpiledBridged {
                        skipYamlModule += """
                          bridging: true

                        """
                    }
                }

                try skipYamlModule.write(to: sourceSkipYamlFile, atomically: false, encoding: .utf8)
            }

            let viewModelInAppModule = modules.count <= 1
            // when the viewModel is part of the same package as the main app, do not include
            let viewModelImport = """
            import \(native ? "SkipFuse" : "OSLog")
            
            """

            let viewModelLog = viewModelInAppModule ? "" : """

            /// A logger for the \(moduleName) module.
            let logger: Logger = Logger(subsystem: "\(modulePackage)", category: "\(moduleName)")

            """

            let viewModelPublic = viewModelInAppModule ? "" : "public "

            let viewModelSourceFile = sourceDir.appending(path: "ViewModel.swift")
            let viewModelCode = """
\(sourceHeader)import Foundation
import Observation
\(viewModelImport)\(viewModelLog)
/// The Observable ViewModel used by the application.
@Observable public class ViewModel {
    \(viewModelPublic)var items: [Item] = loadItems() {
        didSet { saveItems() }
    }

    \(viewModelPublic)init() {
    }

    \(viewModelPublic)func clear() {
        items.removeAll()
    }

    \(viewModelPublic)func isUpdated(_ item: Item) -> Bool {
        item != items.first { i in
            i.id == item.id
        }
    }

    \(viewModelPublic)func save(item: Item) {
        items = items.map { i in
            i.id == item.id ? item : i
        }
    }
}

/// An individual item held by the ViewModel
\(viewModelPublic)struct Item : Identifiable, Hashable, Codable {
    \(viewModelPublic)let id: UUID
    \(viewModelPublic)var date: Date
    \(viewModelPublic)var favorite: Bool
    \(viewModelPublic)var title: String
    \(viewModelPublic)var notes: String

    \(viewModelPublic)init(id: UUID = UUID(), date: Date = .now, favorite: Bool = false, title: String = "", notes: String = "") {
        self.id = id
        self.date = date
        self.favorite = favorite
        self.title = title
        self.notes = notes
    }

    \(viewModelPublic)var itemTitle: String {
        !title.isEmpty ? title : dateString
    }

    \(viewModelPublic)var dateString: String {
        date.formatted(date: .complete, time: .omitted)
    }

    \(viewModelPublic)var dateTimeString: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Utilities for defaulting and persising the items in the list
extension ViewModel {
    private static let savePath = URL.applicationSupportDirectory.appendingPathComponent("appdata.json")

    fileprivate static func loadItems() -> [Item] {
        do {
            let start = Date.now
            let data = try Data(contentsOf: savePath)
            defer {
                let end = Date.now
                logger.info("loaded \\(data.count) bytes from \\(Self.savePath.path) in \\(end.timeIntervalSince(start)) seconds")
            }
            return try JSONDecoder().decode([Item].self, from: data)
        } catch {
            // perhaps the first launch, or the data could not be read
            logger.warning("failed to load data from \\(Self.savePath), using defaultItems: \\(error)")
            let defaultItems = (1...365).map { Date(timeIntervalSinceNow: Double($0 * 60 * 60 * 24 * -1)) }
            return defaultItems.map({ Item(date: $0) })
        }
    }

    fileprivate func saveItems() {
        do {
            let start = Date.now
            let data = try JSONEncoder().encode(items)
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try data.write(to: Self.savePath)
            let end = Date.now
            logger.info("saved \\(data.count) bytes to \\(Self.savePath.path) in \\(end.timeIntervalSince(start)) seconds")
        } catch {
            logger.error("error saving data: \\(error)")
        }
    }
}

"""

            if shouldOutputModel {
                try viewModelCode.write(to: viewModelSourceFile, atomically: false, encoding: .utf8)
            } else if !isAppModule {
                // we need to output *something*, so just make an empty class
                let moduleSwiftFile = sourceDir.appending(path: "\(moduleName).swift")

                var moduleCode = """
\(sourceHeader)import Foundation

public class \(moduleName)Module {

"""

                if isNativeModule {
                    moduleCode += """

    public static func create\(moduleName)Type(id: UUID, delay: Double? = nil) async throws -> \(moduleName)Type {
        if let delay = delay {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        return \(moduleName)Type(id: id)
    }

    /// An example of a type that can be bridged between Swift and Kotlin
    public struct \(moduleName)Type: Identifiable, Hashable, Codable {
        public var id: UUID
    }

"""
                }

                moduleCode += """
}
\(sourceFooter)
"""

                try moduleCode.write(to: moduleSwiftFile, atomically: false, encoding: .utf8)
            }

            let resourcesAttribute: String = resourceFolder.flatMap { resourceFolder in ", resources: [.process(\"\(resourceFolder)\")]" } ?? ""

            if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                let sourceResourcesDir = try sourceDir.append(path: resourceFolder, create: true)
                let sourceResourcesFile = sourceResourcesDir.appending(path: "Localizable.xcstrings")
                try """
{
  "sourceLanguage" : "en",
  "strings" : {
    "%lld Items" : {
      "comment" : "Header title for a list that contains the number of items",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld elementos"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld éléments"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "アイテム数 %lld"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "%lld 个条目"
          }
        }
      }
    },
    "Add" : {
      "comment" : "Button in items list that will cause a new item to be added",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Añadir"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Ajouter"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "追加"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "添加"
          }
        }
      }
    },
    "Appearance" : {
      "comment" : "Settings select label for the interface style of the controls (light, dark, or default)",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apariencia"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Apparence"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "外観"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "外观"
          }
        }
      }
    },
    "Cancel" : {
      "comment" : "Button title indicating that the operation should be cancelled",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Cancelar"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Annuler"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "キャンセル"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "取消"
          }
        }
      }
    },
    "Dark" : {
      "comment" : "Menu item indicating that the appearance should be in dark mode",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Oscuro"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sombre"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "ダーク"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "深色"
          }
        }
      }
    },
    "Date" : {
      "comment" : "Item editor form label for the Date field",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Fecha"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Date"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "日付"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "日期"
          }
        }
      }
    },
    "Favorite" : {
      "comment" : "Item editor title label for marking the item as a favorite",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Favorito"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Favori"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "お気に入り"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "收藏"
          }
        }
      }
    },
    "Hello [%@](https://skip.dev)!" : {
      "comment" : "Welcome tab contents",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "¡Hola [%@](https://skip.dev)!"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bonjour [%@](https://skip.dev)!"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "こんにちは [%@](https://skip.dev)"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "你好 [%@](https://skip.dev)"
          }
        }
      }
    },
    "Home" : {
      "comment" : "Tab bar item title for the Home tab",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Inicio"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Accueil"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "ホーム"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "首页"
          }
        }
      }
    },
    "Light" : {
      "comment" : "Menu item indicating that the appearance should be in light mode",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Claro"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Clair"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "明るい"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "浅色"
          }
        }
      }
    },
    "Name" : {
      "comment" : "Placeholder title for the Name field in a form",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nombre"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Nom"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "名前"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "姓名"
          }
        }
      }
    },
    "Notes" : {
      "comment" : "Item editor form label for the Notes field",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notas"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Notes"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "ノート"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "笔记"
          }
        }
      }
    },
    "Powered by [Skip](https://skip.dev)" : {
      "comment" : "Link markdown text for the Powered by… label",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Impulsado por [Skip](https://skip.dev)"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Fonctionnalités offertes par [Skip](https://skip.dev)"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "[Skip](https://skip.dev) を使って動かしています"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "由[Skip](https://skip.dev)提供支持"
          }
        }
      }
    },
    "Save" : {
      "comment" : "Button title indicating that the current contents should be saved",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Guardar"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Enregistrer"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "保存"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "保存"
          }
        }
      }
    },
    "Settings" : {
      "comment" : "Tab bar item title for the Settings tab",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Configuración"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Paramètres"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "設定"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "设置"
          }
        }
      }
    },
    "System" : {
      "comment" : "Menu item indicating that the appearance should be in the default system mode",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Sistema"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Système"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "システム"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "系统"
          }
        }
      }
    },
    "Title" : {
      "comment" : "Label for the item editor form indicating the title of the item",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Título"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Titre"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "タイトル"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "标题"
          }
        }
      }
    },
    "Version %@ (%@)" : {
      "comment" : "Settings label showing the current version of the app",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "new",
            "value" : "Version %1$@ (%2$@)"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Versión %1$@ (%2$@)"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Version %1$@ (%2$@)"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "バージョン %1$@ (%2$@)"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "版本 %1$@ (%2$@)"
          }
        }
      }
    },
    "Welcome" : {
      "comment" : "Tab bar item title for the Welcome tab",
      "localizations" : {
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bienvenido"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Bienvenue"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "ようこそ"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "欢迎"
          }
        }
      }
    }
  },
  "version" : "1.0"
}

""".write(to: sourceResourcesFile, atomically: false, encoding: .utf8)
            }

            // only create tests if we have specified to do so, and we are not a dependent native module
            let createTestModule = createModuleTests && !isDependentNativeModule && !isNativeAppModule

            if createTestModule {
                let testsURL = try projectFolderURL.append(path: "Tests", create: true)
                let testDir = try testsURL.append(path: moduleName + "Tests", create: true)
                let testSkipDir = try testDir.append(path: "Skip", create: true)
                let testSwiftFile = testDir.appending(path: "\(moduleName)Tests.swift")

                let rfolder = isNativeModule ? nil : resourceFolder

                var testCaseCode = """
\(testSourceHeader)import XCTest
import OSLog
import Foundation

"""

                if isNativeModule {
                    testCaseCode += """
import SkipBridge

"""
                }

                testCaseCode += """
@testable import \(moduleName)

let logger: Logger = Logger(subsystem: "\(moduleName)", category: "Tests")

@available(macOS 13, *)
final class \(moduleName)Tests: XCTestCase {

"""

                if isNativeModule {
                    testCaseCode += """
    override func setUp() {
        #if os(Android)
        // needed to load the compiled bridge from the transpiled tests
        loadPeerLibrary(packageName: "\(projectName)", moduleName: "\(moduleName)")
        #endif
    }

"""
                }

                testCaseCode += """

    func test\(moduleName)() throws {
        logger.log("running test\(moduleName)")
        XCTAssertEqual(1 + 2, 3, "basic test")
    }

"""

                if let folderName = rfolder {
                    testCaseCode += """

    func testDecodeType() throws {
        // load the TestData.json file from the \(folderName) folder and decode it into a struct
        let resourceURL: URL = try XCTUnwrap(Bundle.module.url(forResource: "TestData", withExtension: "json"))
        let testData = try JSONDecoder().decode(TestData.self, from: Data(contentsOf: resourceURL))
        XCTAssertEqual("\(moduleName)", testData.testModuleName)
    }

"""
                }

                if isNativeModule && (isModelModule || isNativeAppModule) {
                    testCaseCode += """

    func testViewModel() async throws {
        let vm = ViewModel()
        vm.items.append(Item(title: "ABC"))
        XCTAssertFalse(vm.items.isEmpty)
        XCTAssertEqual("ABC", vm.items.last?.title)

        vm.clear()
        XCTAssertTrue(vm.items.isEmpty)
    }

"""

                } else if isNativeModule {
                    testCaseCode += """

    func testAsyncThrowsFunction() async throws {

"""
                    if moduleMode == .native || moduleMode == .nativeBridged {
                        testCaseCode += """
        let id = UUID()

"""
                    } else if moduleMode == .kotlincompat {
                        testCaseCode += """
        #if SKIP
        // when the native module is in kotlincompat, types are unwrapped Java classes
        let id = java.util.UUID.randomUUID()
        #else
        let id = UUID()
        #endif

"""
                    }

                    testCaseCode += """
        let type: \(moduleName)Module.\(moduleName)Type = try await \(moduleName)Module.create\(moduleName)Type(id: id, delay: 0.001)
        XCTAssertEqual(id, type.id)
    }

"""
                }


                testCaseCode += """

}

"""
                if rfolder != nil {
                    testCaseCode += """

struct TestData : Codable, Hashable {
    var testModuleName: String
}

"""
                }

                try testCaseCode.write(to: testSwiftFile, atomically: false, encoding: .utf8)

                let skipYamlAppTests = """
                # # Skip configuration for \(moduleName) module
                #build:
                #  contents:
                """

                let skipYamlModuleTests = """
                # # Skip configuration for \(moduleName) module
                #build:
                #  contents:
                """

                let testSkipYamlFile = testSkipDir.appending(path: "skip.yml")
                try (isAppModule ? skipYamlAppTests : skipYamlModuleTests).write(to: testSkipYamlFile, atomically: false, encoding: .utf8)

                if let resourceFolder = resourceFolder, !resourceFolder.isEmpty {
                    let testResourcesDir = try testDir.append(path: resourceFolder, create: true)
                    let testResourcesFile = testResourcesDir.appending(path: "TestData.json")
                    try """
                    {
                      "testModuleName": "\(moduleName)"
                    }
                    """.write(to: testResourcesFile, atomically: false, encoding: .utf8)
                }
            }

            // when we are an app module, override the module name with the product name, since we need a distinct name for importing into the project
            if isAppModule {
                products += """
                        .library(name: "\(productName ?? moduleName)", type: .dynamic, targets: ["\(moduleName)"]),

                """
            } else {
                products += """
                        .library(name: "\(moduleName)", type: .dynamic, targets: ["\(moduleName)"]),

                """
            }

            var moduleDeps: [String] = []
            if let nextModuleName = nextModuleName, options.chain == true {
                moduleDeps.append("\"" + nextModuleName + "\"") // the internal module names are just referred to by string
            }

            var modDeps = module.dependencies
            if modDeps.isEmpty {
                // add implicit dependency on SkipUI (for app target), SkipModel, and SkipFoundation, based in their position in the chain
                if isAppModule {
                    if isNativeAppModule {
                        modDeps.append(PackageModule(repositoryName: "skip-fuse-ui", moduleName: "SkipFuseUI"))
                    } else {
                        modDeps.append(PackageModule(repositoryName: "skip-ui", moduleName: "SkipUI"))
                    }
                } else if (isFinalModule || options.chain == false) && !isDependentNativeModule {
                    // only add SkipFoundation to the innermost module
                    if isNativeModule {
                        modDeps.append(PackageModule(repositoryName: "skip-fuse", moduleName: "SkipFuse"))
                    } else {
                        modDeps.append(PackageModule(repositoryName: "skip-foundation", moduleName: "SkipFoundation"))
                    }
                }

                // in addition to a top-level dependency on SkipUI and a bottom-level dependency on SkipFoundation, a secondary module will also have a dependency on SkipModel for observability
                if isModelModule {
                    // skip-model is a dependency of skip-fuse
                    modDeps.append(PackageModule(repositoryName: "skip-model", moduleName: "SkipModel"))
                    if isNativeModule {
                        modDeps.append(PackageModule(repositoryName: "skip-fuse", moduleName: "SkipFuse"))
                    }
                }
            }
            var skipModuleDeps: [String] = []
            for modDep in modDeps {
                if let repoName = modDep.repositoryName {
                    let repoURL = modDep.organizationName != nil ? "https://github.com/\(modDep.organizationName!)" : "https://source.skip.tools"
                    var packDep = ".package(url: \"\(repoURL)/\(repoName).git\", "

                    var depVersion = modDep.repositoryVersion ?? "1.0.0" // "1.2.3"..<"1.2.6"
                    // special-case skip modules that may not yet be stable by pinning to 0.0.0..<2.0.0
                    if repoName.hasPrefix("skip-") && !["skip", "skip-unit", "skip-lib", "skip-foundation", "skip-model", "skip-ui", "skip-fuse", "skip-fuse-ui"].contains(repoName) {
                        //#if DEBUG
                        //depVersion = "main"
                        //#else
                        depVersion = "0.0.0\"..<\"2.0.0"
                        //#endif
                    }
                    let isRange = depVersion.contains("..")
                    let isSemanticVersion = !depVersion.split(separator: ".").map({ Int($0) }).contains(nil)

                    if isRange {
                        // no qualifier for package range
                    } else if isSemanticVersion {
                        packDep += "from: "
                    } else {
                        // if the version was not of the form 1.2.3, then we consider the version to be a branch
                        packDep += "branch: "
                    }
                    packDep += "\"\(depVersion)\""
                    packDep += ")"

                    if !packageDependencies.contains(packDep) {
                        packageDependencies.append(packDep)
                    }
                    var dep = ".product(name: \"\(modDep.moduleName)\", package: \"\(repoName)\""
                    if let condition = modDep.condition {
                        dep += ", condition: \(condition)"
                    }
                    dep += ")"
                    if !skipModuleDeps.contains(dep) {
                        skipModuleDeps.append(dep)
                    }
                }
            }

            let bracket = { $0.isEmpty ? "[]" : "[\n            " + $0 + "\n        ]" }
            let interModuleDep = moduleDeps.joined(separator: ",\n            ")
            let skipModuleDep = skipModuleDeps.joined(separator: ",\n            ")

            let moduleDep = !interModuleDep.isEmpty && !skipModuleDep.isEmpty
                ? (bracket(interModuleDep + ",\n            " + skipModuleDep))
                : !skipModuleDep.isEmpty
                    ? (bracket(skipModuleDep))
                : bracket(interModuleDep)

            let pluginSuffix = isDependentNativeModule ? "" : ", plugins: \(skipPluginArray)"

            targets += """
                    .target(name: "\(moduleName)", dependencies: \(moduleDep)\(resourcesAttribute)\(pluginSuffix)),

            """

            if createTestModule {
                let skipTestProduct = #".product(name: "SkipTest", package: "skip")"#
                let skipTestDependency = ",\n            \(skipTestProduct)\n        ]"

                targets += """
                        .testTarget(name: "\(moduleName)Tests", dependencies: [
                            "\(moduleName)"\(skipTestDependency)\(resourcesAttribute), plugins: \(skipPluginArray)),

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

        var packageSource = """
        \(packageHeader)
        let package = Package(
            name: "\(projectName)",
            defaultLocalization: "en",
            platforms: [.iOS(.v\(Int(options.iOSMinVersion))), .macOS(.v\(Int(options.macOSMinVersionCalculated)))],
        \(products),
        \(dependencies),
        \(targets)
        )

        """
        if moduleMode == .transpiledBridged {
            packageSource += """

            if Context.environment["SKIP_BRIDGE"] ?? "0" != "0" {
                package.dependencies += [.package(url: "https://source.skip.tools/skip-bridge.git", "0.0.0"..<"2.0.0")]
                package.targets.forEach({ target in
                    target.dependencies += [.product(name: "SkipBridge", package: "skip-bridge")]
                })
                // all library types must be dynamic to support bridging
                package.products = package.products.map({ product in
                    guard let libraryProduct = product as? Product.Library else { return product }
                    return .library(name: libraryProduct.name, type: .dynamic, targets: libraryProduct.targets)
                })
            }

            """
        }

        if options.zero {
            packageSource += """

            // Setting the SKIP_ZERO=1 environment will strip out the Skip plugin and all Skip dependencies
            if Context.environment["SKIP_ZERO"] ?? "0" != "0" {
                package.targets.forEach { target in
                    // remove the Skip plugin
                    target.plugins?.removeAll(where: {
                        if case .plugin(let name, _) = $0 {
                            return name == "skipstone"
                        } else {
                            return false
                        }
                    })

                    // remove the Skip target dependencies
                    target.dependencies.removeAll(where: { dependency in
                        if case .productItem(_, let package, _, _) = dependency {
                            return package == "skip" || package?.hasPrefix("skip-") == true
                        } else {
                            return false
                        }
                    })
                }

                // remove the Skip package dependencies
                package.dependencies.removeAll(where: { dependency in
                    if case .sourceControl(_, let url, _) = dependency.kind {
                        return url.hasPrefix("https://source.skip.dev/") || url.hasPrefix("https://source.skip.tools/")
                    } else {
                        return false
                    }
                })
            }

            """
        }

        let packageSwiftURL = projectFolderURL.appending(path: "Package.swift")
        try packageSource.write(to: packageSwiftURL, atomically: false, encoding: .utf8)

        // now snapshot the file tree for inclusion in the README
        // let fileTree = try localFileSystem.treeASCIIRepresentation(at: projectFolderURL.absolutePath, hideHiddenFiles: true)

        // if we've specified a Package.resolved source file, simply copy it over in order to re-use the pinned dependencies
        if let packageResolvedURL = packageResolvedURL {
            try FileManager.default.copyItem(at: packageResolvedURL, to: projectFolderURL.appending(path: "Package.resolved"))
        }

        let readmeURL = projectFolderURL.appending(path: "README.md")
        let primaryModuleName = modules.first?.moduleName ?? "Module"

        var libREADME = """
        # \(primaryModuleName)

        This is a \(options.free ? "free " : "")[Skip](https://skip.dev) Swift/Kotlin library project containing the following modules:

        \(modules.map(\.moduleName).joined(separator: "\n"))

        ## Building

        This project is a \(options.free ? "free " : "")Swift Package Manager module that uses the
        [Skip](https://skip.dev) plugin to transpile Swift into Kotlin.

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

        if options.free {
            if SourceLicense.allCases.first == .osl {
                libREADME += """
                
                ## License

                This software is licensed under the [Open Software License version 3.0](https://opensource.org/license/osl-3-0).

                """
            } else {
                libREADME += """
                
                ## License
                
                This software is licensed under the
                [GNU Lesser General Public License v3.0](https://spdx.org/licenses/LGPL-3.0-only.html),
                with a [linking exception](https://spdx.org/licenses/LGPL-3.0-linking-exception.html)
                to clarify that distribution to restricted environments (e.g., app stores) is permitted.

                """
            }
        }

        let appStoreLinks = options.appfair ? """
        <!-- TODO: fill in details when releasing to app/play store
        <div align="center">
          <a href="https://play.google.com/store/apps/details?id=ANDROID_APP_ID" style="display: inline-block;"><img src="https://appfair.org/assets/badges/google-play-store.svg" alt="Download on the Google Play Store" style="height: 60px; vertical-align: middle; object-fit: contain;" /></a>
          <a href="https://apps.apple.com/us/app/APPLE_APP_NAME/idAPPLE_APP_ID" style="display: inline-block;"><img src="https://appfair.org/assets/badges/apple-app-store.svg" alt="Download on the Apple App Store" style="height: 60px; vertical-align: middle; object-fit: contain;" /></a>
        </div>
        -->
        

        """ : ""

        var appREADME = """
        # \(primaryModuleName)

        This is a \(options.free ? "free and open-source " : "")[Skip](https://skip.dev) dual-platform app project\(options.appfair ? " distributed through the [App Fair](https://appfair.org)" : "").

        \(appStoreLinks)
        <!-- TODO: add iOS screenshots to fastlane metadata
        ## iPhone Screenshots

        <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/1_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/2_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/3_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/4_en-US.png" style="width: 18%" /> <img alt="iPhone Screenshot" src="Darwin/fastlane/screenshots/en-US/5_en-US.png" style="width: 18%" />
        -->

        <!-- TODO: add Android screenshots to fastlane metadata
        ## Android Screenshots

        <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/1_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/2_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/3_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/4_en-US.png" style="width: 18%" /> <img alt="Android Screenshot" src="Android/fastlane/metadata/android/en-US/images/phoneScreenshots/5_en-US.png" style="width: 18%" />
        -->

        ## Building

        This project is both a stand-alone Swift Package Manager module,
        as well as an Xcode project that builds and translates the project
        into a Kotlin Gradle project for Android using the skipstone plugin.

        Building the module requires that Skip be installed using
        [Homebrew](https://brew.sh) with `brew install skiptools/skip/skip`.

        This will also install the necessary Skip prerequisites:
        Kotlin, Gradle, and the Android build tools.

        Installation prerequisites can be confirmed by running
        `skip checkup`. The project can be validated with `skip verify`.

        ## Running

        Xcode and Android Studio must be downloaded and installed in order to
        run the app in the iOS simulator / Android emulator.
        An Android emulator must already be running, which can be launched from
        Android Studio's Device Manager.

        The project can be opened and run in Xcode from
        `Project.xcworkspace`, which also enabled parallel
        development of any Skip libary dependencies.

        To run both the Swift and Kotlin apps simultaneously,
        launch the "\(primaryModuleName) App" target from Xcode.
        A build phases runs the "Launch Android APK" script that
        will deploy the Skip app to a running Android emulator or connected device.
        Logging output for the iOS app can be viewed in the Xcode console, and in
        Android Studio's logcat tab for the transpiled Kotlin app, or
        using `adb logcat` from a terminal.

        ## Testing

        The module can be tested using the standard `swift test` command
        or by running the test target for the macOS destination in Xcode,
        which will run the Swift tests as well as the transpiled
        Kotlin JUnit tests in the Robolectric Android simulation environment.

        Parity testing can be performed with `skip test`,
        which will output a table of the test results for both platforms.

        """

        if let license {
            appREADME += """
            
            ## License

            This software is licensed under the [\(license.spdx.name)](\(license.spdx.href)).

            """

            try license.licenseContents
                .write(to: projectFolderURL.appending(path: license.licenseFilename), atomically: false, encoding: .utf8)
        }

        try (app ? appREADME : libREADME).write(to: readmeURL, atomically: false, encoding: .utf8)

        // create the .gitignore file; https://github.com/orgs/skiptools/discussions/208#discussioncomment-10505250
        let gitignore = """
## User settings

# vi
.*.swp
.*.swo

# macOS
.DS_Store

# gradle properties
local.properties
.gradle/
.android/
.kotlin/
Android/app/keystore.jks
Android/app/keystore.properties

xcodebuild*.log

default.profraw
*.mobileprovision
*.cer
*.p12
*.p12.password

# Xcode automatically generates this directory with a .xcworkspacedata file and xcuserdata
# hence it is not needed unless you have added a package configuration file to your project
.swiftpm
.build/
build/
DerivedData/
xcuserdata/
xcodebuild*.log
.idea/

*.moved-aside
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3
*.xcscmblueprint
*.xccheckout

## Obj-C/Swift specific
*.hmap

## App packaging
*.ipa
*.dSYM.zip
*.dSYM

## Playgrounds
timeline.xctimeline
playground.xcworkspace

# Swift Package Manager
#
# Add this line if you want to avoid checking in source code from Swift Package Manager dependencies.
Packages/
Package.pins
Package.resolved
#*.xcodeproj

Carthage/Build/

# fastlane

**/fastlane/apikey.json
**/fastlane/report.xml
**/fastlane/README.md
**/fastlane/Preview.html
**/fastlane/test_output

"""

        try gitignore.write(to: outputFolder.appending(path: ".gitignore"), atomically: false, encoding: .utf8)


        return projectFolderURL
    }
}

class AppProjectLayout : FrameworkProjectLayout {
    // the suffix for the product name; this needs to be different from the Xcode project's scheme name or else trying to build the app name target will randomly alternate between trying to build the Xcode app or the SwiftPM app framework
    //static let appProductSuffix = "App"
    static let appProductSuffix = ""

    // the suffix for the Xcode project, which enables us to disambiguate the target name from the Xcode side
    static let appTargetSuffix = " App"

    let moduleName: String

    let skipEnv: URL

    let sourcesFolder: URL
    let moduleSourcesFolder: URL
    let moduleSourcesSkipFolder: URL
    let moduleSourcesSkipConfig: URL
    let testsFolder: URL
    let moduleTestsFolder: URL
    let moduleResourcesFolder: URL

    let workspaceFolder: URL
    let workspaceContents: URL

    let darwinFolder: URL
    let darwinREADME: URL
    let darwinAssetsFolder: URL
    let darwinAssetsContents: URL
    let darwinAccentColorFolder: URL
    let darwinAccentColorContents: URL
    let darwinAppIconFolder: URL
    let darwinAppIconContents: URL

    let darwinModuleAssetsFolder: URL
    let darwinModuleAssetsFolderContents: URL

    let darwinEntitlementsPlist: URL
    let darwinInfoPlist: URL
    let darwinProjectConfig: URL
    let darwinProjectFolder: URL
    let darwinProjectContents: URL
    let darwinSchemesFolder: URL
    let darwinSourcesFolder: URL
    let darwinMainAppSwift: URL
    let darwinFastlaneFolder: URL

    let androidFolder: URL
    let androidREADME: URL

    let androidGradleProperties: URL
    let androidGradleWrapperProperties: URL
    let androidGradleSettings: URL
    let androidAppFolder: URL
    let androidAppBuildGradle: URL
    let androidAppProguardRules: URL
    let androidAppSrc: URL
    let androidAppSrcMain: URL
    let androidManifest: URL
    let androidAppSrcMainRes: URL
    let androidAppSrcMainKotlin: URL
    let androidFastlaneFolder: URL
    let githubFolder: URL

    var androidFastlaneMetadataFolder: URL { androidFastlaneFolder.appendingPathComponent("metadata/android", isDirectory: true) }
    var darwinFastlaneMetadataFolder: URL { darwinFastlaneFolder.appendingPathComponent("metadata", isDirectory: true) }

    init(moduleName: String, root: URL, check: (URL, Bool) throws -> () = checkURLExists) rethrows {
        self.moduleName = moduleName

        let optional = Self.noURLChecks

        self.skipEnv = try root.resolve("Skip.env", check: check)
        self.githubFolder = root.resolve(".github", check: optional)

        self.sourcesFolder = try root.resolve("Sources/", check: check)
        self.moduleSourcesFolder = try sourcesFolder.resolve(moduleName + "/", check: check)
        self.moduleResourcesFolder = try moduleSourcesFolder.resolve("Resources/", check: check)
        self.moduleSourcesSkipFolder = try moduleSourcesFolder.resolve("Skip/", check: check)
        self.moduleSourcesSkipConfig = try moduleSourcesSkipFolder.resolve("skip.yml", check: check)

        self.testsFolder = root.resolve("Tests/", check: optional) // Tests are optional
        self.moduleTestsFolder = testsFolder.resolve(moduleName + "Tests/", check: optional)

        self.workspaceFolder = root.resolve("Project.xcworkspace/", check: optional)
        self.workspaceContents = workspaceFolder.resolve("contents.xcworkspacedata", check: optional)

        self.darwinFolder = try root.resolve("Darwin/", check: check)
        self.darwinREADME = darwinFolder.resolve("README.md", check: optional)
        self.darwinSourcesFolder = try darwinFolder.resolve("Sources/", check: check)
        self.darwinMainAppSwift = try darwinSourcesFolder.resolve("Main.swift", check: check)
        self.darwinProjectConfig = try darwinFolder.resolve(moduleName + ".xcconfig", check: check)
        self.darwinProjectFolder = try darwinFolder.resolve(moduleName + ".xcodeproj/", check: check)
        self.darwinProjectContents = try darwinProjectFolder.resolve("project.pbxproj", check: check)
        self.darwinSchemesFolder = darwinProjectFolder.resolve("xcshareddata/xcschemes/", check: optional)
        self.darwinEntitlementsPlist = try darwinFolder.resolve("Entitlements.plist", check: check)
        self.darwinInfoPlist = darwinFolder.resolve("Info.plist", check: optional)

        self.darwinAssetsFolder = try darwinFolder.resolve("Assets.xcassets/", check: check)
        self.darwinAssetsContents = try darwinAssetsFolder.resolve("Contents.json", check: check)
        self.darwinAccentColorFolder = try darwinAssetsFolder.resolve("AccentColor.colorset/", check: check)
        self.darwinAccentColorContents = try darwinAccentColorFolder.resolve("Contents.json", check: check)
        self.darwinAppIconFolder = try darwinAssetsFolder.resolve("AppIcon.appiconset/", check: check)
        self.darwinAppIconContents = try darwinAppIconFolder.resolve("Contents.json", check: check)

        self.darwinModuleAssetsFolder = moduleResourcesFolder.resolve("Module.xcassets/", check: optional)
        self.darwinModuleAssetsFolderContents = darwinModuleAssetsFolder.resolve("Contents.json", check: optional)
        // TODO: add logoPDF

        self.darwinFastlaneFolder = darwinFolder.resolve("fastlane/", check: optional)

        self.androidFolder = try root.resolve("Android/", check: check)
        self.androidREADME = androidFolder.resolve("README.md", check: optional)
        self.androidGradleProperties = try androidFolder.resolve("gradle.properties", check: check)
        self.androidGradleWrapperProperties = androidFolder.resolve("gradle/wrapper/gradle-wrapper.properties", check: optional)
        self.androidGradleSettings = try androidFolder.resolve("settings.gradle.kts", check: check)
        self.androidAppFolder = try androidFolder.resolve("app/", check: check)
        self.androidAppBuildGradle = try androidAppFolder.resolve("build.gradle.kts", check: check)
        self.androidAppProguardRules = try androidAppFolder.resolve("proguard-rules.pro", check: check)
        self.androidAppSrc = try androidAppFolder.resolve("src/", check: check)
        self.androidAppSrcMain = try androidAppSrc.resolve("main/", check: check)
        self.androidManifest = try androidAppSrcMain.resolve("AndroidManifest.xml", check: check)
        self.androidAppSrcMainRes = androidAppSrcMain.resolve("res/", check: optional)
        //self.androidAppSrcIconMDPI = try androidAppSrcRes.resolve("mipmap-mdpi/", check: check)
        self.androidAppSrcMainKotlin = try androidAppSrcMain.resolve("kotlin/", check: check)
        self.androidFastlaneFolder = androidFolder.resolve("fastlane/", check: optional)

        //self.androidAppSrcMainKotlinModule = try androidAppSrcMainKotlin.resolve("src/", check: check)

        try super.init(root: root, check: check)
    }

    static func createSkipAppProject(options: ProjectOptionValues, productName: String?, modules: [PackageModule], resourceFolder: String?, dir outputFolder: URL, configuration: BuildConfiguration, build: Bool, test: Bool, app: Bool, appid: String?, icon: IconParameters?, version: String?, nativeMode: NativeMode, moduleMode: ModuleMode, moduleTests: Bool, packageResolved packageResolvedURL: URL? = nil) async throws -> (baseURL: URL, project: AppProjectLayout) {
        let sourceHeader = options.defaultLicense(app: true)?.sourceHeader.appending("\n\n") ?? ""

        let projectName = options.projectName
        if let invalidProjectName = isValidProjectName(projectName) {
            throw InitError(errorDescription: "\(invalidProjectName): \(projectName)")
        }


        if modules.contains(where: { module in
            module.moduleName.lowercased() == projectName.lowercased()
        }) {
            throw InitError(errorDescription: "ModuleName and project-name must be different: \(projectName)")
        }

        for module in modules {
            if let invalidModuleName = isValidModuleName(module.moduleName) {
                throw InitError(errorDescription: "\(invalidModuleName): \(module.moduleName)")
            }
        }

        if let appid = appid {
            if let invalidAppID = isValidBundleIdentifier(appid) {
                throw InitError(errorDescription: "\(invalidAppID): \(appid)")
            }
            if !appid.contains(".") {
                throw InitError(errorDescription: "Appid must be a valid bundle identifier containing at least one dot: \(appid)")
            }
        }

        let projectURL = try createSkipLibrary(options: options, productName: productName, modules: modules, resourceFolder: resourceFolder, dir: outputFolder, app: app, nativeMode: nativeMode, moduleMode: moduleMode, moduleTests: moduleTests, packageResolved: packageResolvedURL)

        // the second module should always be imported
        let secondModule = modules.dropFirst().first

        let projectPath = try projectURL.absolutePath

        let primaryModuleName = modules.first?.moduleName ?? "Module"

        // get the layout of the project for writing files
        let appProject = AppProjectLayout(moduleName: primaryModuleName, root: projectPath.asURL, check: AppProjectLayout.noURLChecks)

        let sourcesFolderName = "Sources"
        let appModuleName = primaryModuleName
        let appModulePackage = try packageName(forModule: appModuleName)

        // The Xcode name for the app
        let APP_NAME = appModuleName
        // The Xcode target/scheme name for the app
        let APP_TARGET = "\(APP_NAME)\(AppProjectLayout.appTargetSuffix)"
        // The Xcode product name for the app
        let APP_PRODUCT = "\(APP_NAME)\(AppProjectLayout.appProductSuffix)" // note: blank for new scheme

        guard app, let appid = appid else { // we have specified that an app should be created
            return (projectURL, appProject)
        }

        try appProject.darwinProjectFolder.createDirectory()

        let primaryModuleAppMainURL = appProject.darwinMainAppSwift
        let primaryModuleSources = sourcesFolderName + "/" + primaryModuleName
        let entitlements_name = appProject.darwinEntitlementsPlist.lastPathComponent
        let entitlements_path = entitlements_name // same folder
        let _ = entitlements_path

        // Sources/PlaygroundApp/Entitlements.plist
        let appEntitlementsContents = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>

"""

        try appEntitlementsContents.write(to: appProject.darwinEntitlementsPlist.createParentDirectory(), atomically: false, encoding: .utf8)

        // Sources/PlaygroundApp/Info.plist
        let infoPlistContents = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
</dict>
</plist>

"""

        try infoPlistContents.write(to: appProject.darwinInfoPlist.createParentDirectory(), atomically: false, encoding: .utf8)

        // create the top-level Skip.env which is the source or truth for Xcode and Gradle
        let skipEnvContents = """
// The configuration file for your Skip App (https://skip.dev).
// Properties specified here are shared between
// Darwin/\(appModuleName).xcconfig and Android/settings.gradle.kts
// and will be included in the app's metadata files
// Info.plist and AndroidManifest.xml

// PRODUCT_NAME is the default title of the app, which must match the app's Swift module name
PRODUCT_NAME = \(appModuleName)

// PRODUCT_BUNDLE_IDENTIFIER is the unique id for both the iOS and Android app
PRODUCT_BUNDLE_IDENTIFIER = \(appid)

// The semantic version of the app
MARKETING_VERSION = \(version ?? "0.0.1")

// The build number specifying the internal app version
CURRENT_PROJECT_VERSION = 1

// The package name for the Android entry point, referenced by the AndroidManifest.xml
ANDROID_PACKAGE_NAME = \(appModulePackage)

// If your Android appId is different from the iOS Bundle Identifer, specify it here
// ANDROID_APPLICATION_ID = \(appid)

"""

        try skipEnvContents.write(to: appProject.skipEnv, atomically: false, encoding: .utf8)
        //let skipEnvFileName = appProject.skipEnv.lastPathComponent

        let skipEnvBaseName = "Skip.env"
        let skipEnvFileName = "../\(skipEnvBaseName)"

        let swiftVersionMajor = options.swiftPackageVersion.split(separator: ".").first ?? "6"

        // create the top-level ModuleName.xcconfig which is the source or truth for the iOS and Android builds
        let configContents = """
#include "\(skipEnvFileName)"

// Set the action that will be executed as part of the Xcode Run Script phase
// Setting to "launch" will build and run the app in the first open Android emulator or device
// Setting to "build" will just run gradle build, but will not launch the app
// Setting to "none" will completely disable the build and launch of the Android app
SKIP_ACTION = launch
//SKIP_ACTION = build
//SKIP_ACTION = none

ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor

INFOPLIST_FILE = Info.plist
GENERATE_INFOPLIST_FILE = YES

// The user-visible name of the app (localizable)
//INFOPLIST_KEY_CFBundleDisplayName = App Name
//INFOPLIST_KEY_LSApplicationCategoryType = public.app-category.utilities
//INFOPLIST_KEY_NSLocationWhenInUseUsageDescription = "This app uses your location to …"

// iOS-specific Info.plist property keys
INFOPLIST_KEY_UIApplicationSceneManifest_Generation[sdk=iphone*] = YES
INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents[sdk=iphone*] = YES
INFOPLIST_KEY_UILaunchScreen_Generation[sdk=iphone*] = YES
INFOPLIST_KEY_UIStatusBarStyle[sdk=iphone*] = UIStatusBarStyleDefault
INFOPLIST_KEY_UISupportedInterfaceOrientations[sdk=iphone*] = UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown

IPHONEOS_DEPLOYMENT_TARGET = \(options.iOSMinVersion)
MACOSX_DEPLOYMENT_TARGET = \(options.macOSMinVersionCalculated)
SUPPORTS_MACCATALYST = NO

// iPhone + iPad
TARGETED_DEVICE_FAMILY = 1,2

// iPhone only
// TARGETED_DEVICE_FAMILY = 1

SWIFT_EMIT_LOC_STRINGS = YES

// the name of the product module; this can be anything, but cannot conflict with any Swift module names
PRODUCT_MODULE_NAME = $(PRODUCT_NAME:c99extidentifier)App

// On-device testing may need to override the bundle ID
// PRODUCT_BUNDLE_IDENTIFIER[config=Debug][sdk=iphoneos*] = cool.beans.BundleIdentifer

SDKROOT = auto
SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx
SWIFT_EMIT_LOC_STRINGS = YES

SWIFT_VERSION = \(swiftVersionMajor)

// Development team ID for on-device testing
CODE_SIGNING_REQUIRED = NO
CODE_SIGN_STYLE = Automatic
CODE_SIGN_ENTITLEMENTS = Entitlements.plist
//CODE_SIGNING_IDENTITY = -
//DEVELOPMENT_TEAM =

"""

        try configContents.write(to: appProject.darwinProjectConfig, atomically: false, encoding: .utf8)
        let xcconfigFileName = appProject.darwinProjectConfig.lastPathComponent
        let _ = xcconfigFileName

        if options.github {
            try createGithubConfig()
        }

        func createGithubConfig() throws {
            try """
# This is a GitHub workflow that will build the Skip app whenever
# a push or release tag is made. In addition, various secrets can be
# enabled for the repository that will automatically publish
# releases to the Apple App Store and/or Google Play Store.
#
# See the documentation at https://skip.dev/docs for more details.
name: \(projectName)
on:
  push:
    branches: [ main ]
    tags: "[0-9]+.[0-9]+.[0-9]+"
  # example of daily scheduled build
  #schedule:
    #- cron: '0 12 * * *'
  workflow_dispatch:
  pull_request:

permissions:
  contents: write
  id-token: write
  attestations: write
jobs:
  call-workflow:
    uses: skiptools/actions/.github/workflows/skip-app.yml@v1
    secrets:
      # These optional secrets enable the Android app to be signed
      KEYSTORE_JKS: ${{ secrets.KEYSTORE_JKS }}
      KEYSTORE_PROPERTIES: ${{ secrets.KEYSTORE_PROPERTIES }}

      # This secret enables the Android app to be uploaded to the Play Store
      GOOGLE_PLAY_APIKEY: ${{ secrets.GOOGLE_PLAY_APIKEY }}

      # These optional secrets enable the iOS app to be signed
      APPLE_CERTIFICATES_P12: ${{ secrets.APPLE_CERTIFICATES_P12 }}
      APPLE_CERTIFICATES_P12_PASSWORD: ${{ secrets.APPLE_CERTIFICATES_P12_PASSWORD }}

      # This secret enables the iOS app to be uploaded to the App Store
      APPLE_APPSTORE_APIKEY: ${{ secrets.APPLE_APPSTORE_APIKEY }}

""".write(to: appProject.githubFolder.appendingPathComponent("workflows/\(projectName).yml").createParentDirectory(), atomically: false, encoding: .utf8)
        }

        if options.fastlane {
            try createFastlaneMetadata()
        }

        func createFastlaneMetadata() throws {
            try createFastlaneAndroidMetadata()
            try createFastlaneDarwinMetadata()
        }

        func createFastlaneAndroidMetadata() throws {
            // README.md
            try """
This is a stock fastlane configuration file for your Skip project.
To use fastlane to distribute your app:

1. Update the metadata text files in metadata/android/en-US/
2. Add screenshots to screenshots/en-US
3. Download your Android API JSON file to apikey.json (see https://docs.fastlane.tools/actions/upload_to_play_store/)
4. Run `fastlane assemble` to build the app
5. Run `fastlane release` to submit a new release to the App Store

For the bundle name and version numbers, the ../Skip.env file will be used.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

""".write(to: appProject.androidFastlaneFolder.appendingPathComponent("README.md").createParentDirectory(), atomically: false, encoding: .utf8)

            // Appfile
            try """
# This file contains the app distribution configuration
# for the Android half of the Skip app.
# You can find the documentation at https://docs.fastlane.tools

# Load the shared Skip.env properties with the app info
require('dotenv')
Dotenv.load('../../Skip.env')
package_name(ENV['PRODUCT_BUNDLE_IDENTIFIER'].sub("-", "_"))

# Path to the json secret file - Follow https://docs.fastlane.tools/actions/supply/#setup to get one
json_key_file("fastlane/apikey.json")

""".write(to: appProject.androidFastlaneFolder.appendingPathComponent("Appfile").createParentDirectory(), atomically: false, encoding: .utf8)

            // Fastfile
            try """
# This file contains the fastlane.tools configuration
# for the Android half of the Skip app.
# You can find the documentation at https://docs.fastlane.tools

# Load the shared Skip.env properties with the app info
require('dotenv')
Dotenv.load '../../Skip.env'

default_platform(:android)

# use the Homebrew gradle rather than expecting a local gradlew
gradle_bin = (ENV['HOMEBREW_PREFIX'] ? ENV['HOMEBREW_PREFIX'] : "/opt/homebrew") + "/bin/gradle"

default_platform(:android)

desc "Build Skip Android App"
lane :build do |options|
  build_config = (options[:release] ? "Release" : "Debug")
  gradle(
    task: "build${build_config}",
    gradle_path: gradle_bin,
    flags: "--warning-mode none -x lint"
  )
end

desc "Test Skip Android App"
lane :test do
  gradle(
    task: "test",
    gradle_path: gradle_bin
  )
end

desc "Assemble Skip Android App"
lane :assemble do
  gradle(
    gradle_path: gradle_bin,
    task: "bundleRelease"
  )
  # sh "your_script.sh"
end

desc "Deploy Skip Android App to Google Play"
lane :release do

  assemble

  upload_to_play_store(
    aab: '../.build/Android/app/outputs/bundle/release/app-release.aab'
  )
end

""".write(to: appProject.androidFastlaneFolder.appendingPathComponent("Fastfile").createParentDirectory(), atomically: false, encoding: .utf8)


            // metadata/android/en-US/full_description.txt
            try """
A great new app built with Skip!

""".write(to: appProject.androidFastlaneMetadataFolder.appendingPathComponent("en-US/full_description.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // metadata/android/en-US/title.txt
            try """
\(appModuleName)

""".write(to: appProject.androidFastlaneMetadataFolder.appendingPathComponent("en-US/title.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // metadata/android/en-US/short_description.txt
            try """
A great new app built with Skip!

""".write(to: appProject.androidFastlaneMetadataFolder.appendingPathComponent("en-US/short_description.txt").createParentDirectory(), atomically: false, encoding: .utf8)


        }

        func createFastlaneDarwinMetadata() throws {
            // README.md
            try """
This is a stock fastlane configuration file for your Skip project.
To use fastlane to distribute your app:

1. Update the metadata text files in metadata/en-US/
2. Add screenshots to screenshots/en-US
3. Download your App Store Connect API JSON file to apikey.json
4. Run `fastlane assemble` to build the app
5. Run `fastlane release` to submit a new release to the App Store

For the bundle name and version numbers, the ../Skip.env file will be used.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).

""".write(to: appProject.darwinFastlaneFolder.appendingPathComponent("README.md").createParentDirectory(), atomically: false, encoding: .utf8)

            // Fastfile
            try """
# This file contains the fastlane.tools configuration
# for the iOS half of the Skip app.
# You can find the documentation at https://docs.fastlane.tools

default_platform(:ios)

lane :assemble do |options|
  # only build the iOS side of the app
  ENV["SKIP_ZERO"] = "true"
  build_app(
    scheme: "\(APP_TARGET)",
    sdk: "iphoneos",
    xcconfig: "fastlane/AppStore.xcconfig",
    xcargs: "-skipPackagePluginValidation -skipMacroValidation",
    derived_data_path: "../.build/Darwin/DerivedData",
    output_directory: "../.build/fastlane/Darwin",
    skip_archive: ENV["FASTLANE_SKIP_ARCHIVE"] == "YES",
    skip_codesigning: ENV["FASTLANE_SKIP_CODESIGNING"] == "YES"
  )
end

lane :release do |options|
  desc "Build and release app"

  # see https://docs.fastlane.tools/uploading-app-privacy-details/
  #upload_app_privacy_details_to_app_store(json_path: "fastlane/app_privacy_details.json")

  # if you have an apikey.json file (https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api), fastlane can automatically fetch certificates and the ASC authentication information
  #get_certificates(api_key_path: "fastlane/apikey.json")
  get_provisioning_profile(api_key_path: "fastlane/apikey.json")

  assemble

  upload_to_app_store(
    api_key_path: "fastlane/apikey.json",
    app_rating_config_path: "fastlane/metadata/rating.json",
    release_notes: { default: "Fixes and improvements." }
  )
end


""".write(to: appProject.darwinFastlaneFolder.appendingPathComponent("Fastfile").createParentDirectory(), atomically: false, encoding: .utf8)

            // Appfile
            try """
# For more information about the Appfile, see:
#     https://docs.fastlane.tools/advanced/#appfile

require('dotenv')
Dotenv.load '../../Skip.env'
app_identifier(ENV['ANDROID_APPLICATION_ID'] || ENV['PRODUCT_BUNDLE_IDENTIFIER'])

# apple_id("my@email")

""".write(to: appProject.darwinFastlaneFolder.appendingPathComponent("Appfile").createParentDirectory(), atomically: false, encoding: .utf8)

            // Deliverfile
            try """

copyright "#{Time.now.year}"

force(true) # Skip HTML report verification
automatic_release(true)
skip_screenshots(false)
precheck_include_in_app_purchases(false)

#skip_binary_upload(true)
submit_for_review(true)

submission_information({
    add_id_info_serves_ads: false,
    add_id_info_uses_idfa: false,
    add_id_info_tracks_install: false,
    add_id_info_tracks_action: false,
    add_id_info_limits_tracking: false,
    content_rights_has_rights: false,
    content_rights_contains_third_party_content: false,
    export_compliance_contains_third_party_cryptography: false,
    export_compliance_encryption_updated: false,
    export_compliance_platform: 'ios',
    export_compliance_compliance_required: false,
    export_compliance_uses_encryption: false,
    export_compliance_is_exempt: false,
    export_compliance_contains_proprietary_cryptography: false
})

""".write(to: appProject.darwinFastlaneFolder.appendingPathComponent("Deliverfile").createParentDirectory(), atomically: false, encoding: .utf8)

            // AppStore.xcconfig
            try """
// Additional properties included by the Fastfile build_app

// This file can be used to override various properties from Skip.env
//PRODUCT_BUNDLE_IDENTIFIER =
//DEVELOPMENT_TEAM =

""".write(to: appProject.darwinFastlaneFolder.appendingPathComponent("AppStore.xcconfig").createParentDirectory(), atomically: false, encoding: .utf8)

            // app_privacy_details.json
            try """
[
  {
    "data_protections": [
      "DATA_NOT_COLLECTED"
    ]
  }
]

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("app_privacy_details.json").createParentDirectory(), atomically: false, encoding: .utf8)

            // rating.json
            try """
{
  "advertising": false,
  "ageAssurance": false,
  "gambling": false,
  "healthOrWellnessTopics": false,
  "lootBox": false,
  "messagingAndChat": false,
  "parentalControls": false,
  "unrestrictedWebAccess": false,
  "userGeneratedContent": false,
  "alcoholTobaccoOrDrugUseOrReferences": "NONE",
  "contests": "NONE",
  "gamblingSimulated": "NONE",
  "gunsOrOtherWeapons": "NONE",
  "horrorOrFearThemes": "NONE",
  "koreaAgeRatingOverride": "NONE",
  "matureOrSuggestiveThemes": "NONE",
  "medicalOrTreatmentInformation": "NONE",
  "profanityOrCrudeHumor": "NONE",
  "sexualContentGraphicAndNudity": "NONE",
  "sexualContentOrNudity": "NONE",
  "violenceCartoonOrFantasy": "NONE",
  "violenceRealistic": "NONE",
  "violenceRealisticProlongedGraphicOrSadistic": "NONE"
}

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("rating.json").createParentDirectory(), atomically: false, encoding: .utf8)

            // description.txt
            try """
A great new app built with Skip!

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/description.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // keywords.txt
            try """
app,key,words

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/keywords.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // privacy_url.txt
            try """
https://example.org/privacy/

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/privacy_url.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // release_notes.txt
            try """
Bug fixes and performance improvements.

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/release_notes.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // software_url.txt
            try """
https://example.org/app/

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/software_url.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // subtitle.txt
            try """
A new Skip app

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/subtitle.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // support_url.txt
            try """
https://example.org/support/

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/support_url.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // title.txt
            try """
\(appModuleName)

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/title.txt").createParentDirectory(), atomically: false, encoding: .utf8)

            // version_whats_new.txt
            try """
New features and better performance.

""".write(to: appProject.darwinFastlaneMetadataFolder.appendingPathComponent("en-US/version_whats_new.txt").createParentDirectory(), atomically: false, encoding: .utf8)

        }

        let isNativeAppModule = nativeMode.contains(.nativeApp)
        let swiftUIImport = "import SwiftUI"
        let osLogImport = isNativeAppModule ? "import SkipFuse" : "import OSLog"
        // explicitly bridge the public app functions that need to be accessed from Main.kt
        let skipBridge = isNativeAppModule ? "/* SKIP @bridge */" : ""

        // Darwin/Sources/Main.swift
        let appMainContents = """
\(sourceHeader)import SwiftUI
import \(primaryModuleName)

private typealias AppRootView = \(primaryModuleName)RootView
private typealias AppDelegate = \(primaryModuleName)AppDelegate

/// The entry point to the app simply loads the App implementation from SPM module.
@main struct AppMain: App {
    @AppDelegateAdaptor(AppMainDelegate.self) var appDelegate
    @Environment(\\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                AppDelegate.shared.onResume()
            case .inactive:
                AppDelegate.shared.onPause()
            case .background:
                AppDelegate.shared.onStop()
            @unknown default:
                print("unknown app phase: \\(newPhase)")
            }
        }
    }
}

#if canImport(UIKit)
typealias AppDelegateAdaptor = UIApplicationDelegateAdaptor
typealias AppMainDelegateBase = UIApplicationDelegate
typealias AppType = UIApplication
#elseif canImport(AppKit)
typealias AppDelegateAdaptor = NSApplicationDelegateAdaptor
typealias AppMainDelegateBase = NSApplicationDelegate
typealias AppType = NSApplication
#endif

@MainActor final class AppMainDelegate: NSObject, AppMainDelegateBase {
    let application = AppType.shared

    #if canImport(UIKit)
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppDelegate.shared.onInit()
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        AppDelegate.shared.onLaunch()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppDelegate.shared.onDestroy()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        AppDelegate.shared.onLowMemory()
    }

    // support for SkipNotify.fetchNotificationToken()

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: NSNotification.Name("didRegisterForRemoteNotificationsWithDeviceToken"), object: application, userInfo: ["deviceToken": deviceToken])
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        NotificationCenter.default.post(name: NSNotification.Name("didFailToRegisterForRemoteNotificationsWithError"), object: application, userInfo: ["error": error])
    }
    #elseif canImport(AppKit)
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppDelegate.shared.onInit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared.onLaunch()
    }

    func applicationWillTerminate(_ application: Notification) {
        AppDelegate.shared.onDestroy()
    }
    #endif

}

"""
        try appMainContents.write(to: primaryModuleAppMainURL.createParentDirectory(), atomically: false, encoding: .utf8)

        // Sources/Playground/PlaygroundApp.swift
        let appExtContents = """
\(sourceHeader)import Foundation
\(osLogImport)
\(swiftUIImport)

/// A logger for the \(primaryModuleName) module.
let logger: Logger = Logger(subsystem: "\(appid)", category: "\(primaryModuleName)")

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
\(skipBridge)public struct \(primaryModuleName)RootView : View {
    \(skipBridge)public init() {
    }

    public var body: some View {
        ContentView()
            .task {
                logger.info("Skip app logs are viewable in the Xcode console for iOS; Android logs can be viewed in Studio or using adb logcat")
            }
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
\(skipBridge)public final class \(primaryModuleName)AppDelegate : Sendable {
    \(skipBridge)public static let shared = \(primaryModuleName)AppDelegate()

    private init() {
    }

    \(skipBridge)public func onInit() {
        logger.debug("onInit")
    }

    \(skipBridge)public func onLaunch() {
        logger.debug("onLaunch")
    }

    \(skipBridge)public func onResume() {
        logger.debug("onResume")
    }

    \(skipBridge)public func onPause() {
        logger.debug("onPause")
    }

    \(skipBridge)public func onStop() {
        logger.debug("onStop")
    }

    \(skipBridge)public func onDestroy() {
        logger.debug("onDestroy")
    }

    \(skipBridge)public func onLowMemory() {
        logger.debug("onLowMemory")
    }
}

"""

        let appModuleApplicationStubFileBase = appModuleName + "App.swift"
        let appModuleApplicationStubFilePath = primaryModuleSources + "/" + appModuleApplicationStubFileBase

        let appModuleApplicationStubFileURL = projectURL.appending(path: appModuleApplicationStubFilePath)
        try FileManager.default.createDirectory(at: appModuleApplicationStubFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try appExtContents.write(to: appModuleApplicationStubFileURL, atomically: false, encoding: .utf8)

        let secondImport = options.appfair == true ? "\nimport AppFairUI" : ""
        let thirdImport = secondModule.flatMap({ "\nimport \($0.moduleName)" }) ?? ""
        let appOrg = appid.split(separator: ".").last?.description ?? appid
        let appLink = options.appfair == true ? "https://github.com/\(appOrg)/\(appOrg)" : "https://skip.dev"
        let settingsFormView = options.appfair == true ? "AppFairSettings" : "Form"
        let demoSettingsCode = options.appfair == true ? "" : """

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                Text("Version \\(version) (\\(buildNumber))")
            }
            HStack {
                PlatformHeartView()
                Text("Powered by [Skip](https://skip.dev)")
            }
"""

        let nativeAppModulePlatformView = """
/// A view that shows a blue heart on iOS and a green heart on Android.
struct PlatformHeartView : View {
    var body: some View {
        #if os(Android)
        ComposeView {
            HeartComposer()
        }
        #else
        Text(verbatim: "💙")
        #endif
    }
}

#if SKIP
/// Use a ContentComposer to integrate Compose content. This code will be transpiled to Kotlin.
struct HeartComposer : ContentComposer {
    @Composable func Compose(context: ComposeContext) {
        androidx.compose.material3.Text("💚", modifier: context.modifier)
    }
}
#endif

"""

        let transpiledAppModulePlatformView = """
/// A view that shows a blue heart on iOS and a green heart on Android.
struct PlatformHeartView : View {
    var body: some View {
       #if SKIP
       ComposeView { ctx in // Mix in Compose code!
           androidx.compose.material3.Text("💚", modifier: ctx.modifier)
       }
       #else
       Text(verbatim: "💙")
       #endif
    }
}

"""

        // the platform-specific view is different between a native app module and a transpiled module
        let platformHeartView = options.appfair == true ? "" : isNativeAppModule ? nativeAppModulePlatformView : transpiledAppModulePlatformView

        let contentViewTabBodyContents: String
        if options.iOSMinVersion >= 18.0 {
            // iOS 18+ uses newer Tab construct
            contentViewTabBodyContents = """
        TabView(selection: $tab) {
            Tab("Welcome", systemImage: "heart.fill", value: ContentTab.welcome) {
                NavigationStack {
                    WelcomeView(welcomeName: $welcomeName)
                }
            }
            Tab("Home", systemImage: "house.fill", value: ContentTab.home) {
                NavigationStack {
                    ItemListView()
                        .navigationTitle(Text("\\(viewModel.items.count) Items"))
                }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: ContentTab.settings) {
                NavigationStack {
                    SettingsView(appearance: $appearance, welcomeName: $welcomeName)
                        .navigationTitle("Settings")
                }
            }
        }
"""
        } else {
            contentViewTabBodyContents = """
        TabView(selection: $tab) {
            NavigationStack {
                WelcomeView(welcomeName: $welcomeName)
            }
            .tabItem { Label("Welcome", systemImage: "heart.fill") }
            .tag(ContentTab.welcome)

            NavigationStack {
                ItemListView()
                    .navigationTitle(Text("\\(viewModel.items.count) Items"))
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(ContentTab.home)

            NavigationStack {
                SettingsView(appearance: $appearance, welcomeName: $welcomeName)
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            .tag(ContentTab.settings)
        }
"""
        }

        // Sources/Playground/PlaygroundApp.swift
        let contentViewContents = """
\(sourceHeader)\(swiftUIImport)\(secondImport)\(thirdImport)

enum ContentTab: String, Hashable {
    case welcome, home, settings
}

struct ContentView: View {
    @AppStorage("tab") var tab = ContentTab.welcome
    @AppStorage("name") var welcomeName = "Skipper"
    @AppStorage("appearance") var appearance = ""
    @State var viewModel = ViewModel()

    var body: some View {
\(contentViewTabBodyContents)
        .environment(viewModel)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
    }
}

struct WelcomeView : View {
    @State var heartBeating = false
    @Binding var welcomeName: String

    var body: some View {
        VStack(spacing: 0) {
            Text("Hello [\\(welcomeName)](\(appLink))!")
                .padding()
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .scaleEffect(heartBeating ? 1.5 : 1.0)
                .animation(.easeInOut(duration: 1).repeatForever(), value: heartBeating)
                .task { heartBeating = true }
        }
        .font(.largeTitle)
    }
}

struct ItemListView : View {
    @Environment(ViewModel.self) var viewModel: ViewModel

    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                NavigationLink(value: item) {
                    Label {
                        Text(item.itemTitle)
                    } icon: {
                        if item.favorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
            .onDelete { offsets in
                viewModel.items.remove(atOffsets: offsets)
            }
            .onMove { fromOffsets, toOffset in
                viewModel.items.move(fromOffsets: fromOffsets, toOffset: toOffset)
            }
        }
        .navigationDestination(for: Item.self) { item in
            ItemView(item: item)
                .navigationTitle(item.itemTitle)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    withAnimation {
                        viewModel.items.insert(Item(), at: 0)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }
}

struct ItemView : View {
    @State var item: Item
    @Environment(ViewModel.self) var viewModel: ViewModel
    @Environment(\\.dismiss) var dismiss

    var body: some View {
        Form {
            TextField("Title", text: $item.title)
                .textFieldStyle(.roundedBorder)
            Toggle("Favorite", isOn: $item.favorite)
            DatePicker("Date", selection: $item.date)
            Text("Notes").font(.title3)
            TextEditor(text: $item.notes)
                .border(Color.secondary, width: 1.0)
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(item: item)
                    dismiss()
                }
                .disabled(!viewModel.isUpdated(item))
            }
        }
    }
}

struct SettingsView : View {
    @Binding var appearance: String
    @Binding var welcomeName: String

    var body: some View {
        \(settingsFormView) {
            TextField("Name", text: $welcomeName)
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }\(demoSettingsCode)
        }
    }
}

\(platformHeartView)
"""

        let contentViewFileBase = "ContentView.swift"
        let contentViewRelativePath = primaryModuleSources + "/" + contentViewFileBase

        let contentViewURL = projectURL.appending(path: contentViewRelativePath)
        try FileManager.default.createDirectory(at: contentViewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contentViewContents.write(to: contentViewURL, atomically: false, encoding: .utf8)


        let Assets_xcassets_URL = try appProject.darwinAssetsFolder.createDirectory()
        let Assets_xcassets_name = appProject.darwinAssetsFolder.lastPathComponent
        let Assets_xcassets_path = Assets_xcassets_name // the path is in the root Darwin/ folder
        let _ = Assets_xcassets_path

        let Assets_xcassets_Contents_URL = appProject.darwinAssetsContents
        let Assets_xcassets_Contents = """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
        try Assets_xcassets_Contents.write(to: Assets_xcassets_Contents_URL, atomically: false, encoding: .utf8)

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
        try Assets_xcassets_AccentColor_Contents.write(to: Assets_xcassets_AccentColor_ContentsURL, atomically: false, encoding: .utf8)

        let Assets_xcassets_AppIcon_Contents: String
        let hasIcon = icon != nil
        if hasIcon {
            let separateLayers = true
            let icons = try await generateIcons(darwinAppIconFolder: appProject.darwinAppIconFolder, androidAppSrcMainRes: appProject.androidAppSrcMainRes, backgroundColor: icon?.iconBackgroundColor, randomBackground: true, foregroundColor: icon?.iconForegroundColor ?? IconCommand.defaultIconForeground, iconSources: icon?.iconSources ?? [], randomIcon: true, shadow: icon?.iconShadow ?? IconCommand.defaultIconShadow, iconInset: icon?.iconInset ?? IconCommand.defaultIconInset, separateLayers: separateLayers)
            let _ = icons

            Assets_xcassets_AppIcon_Contents = """
{
  "images" : [
    {
      "filename" : "AppIcon-20@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "AppIcon-20@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "AppIcon-29.png",
      "idiom" : "iphone",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "AppIcon-29@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "AppIcon-29@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "AppIcon-40@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "AppIcon-40@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "AppIcon@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "AppIcon@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "AppIcon-20~ipad.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20"
    },
    {
      "filename" : "AppIcon-20@2x~ipad.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "AppIcon-29~ipad.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "AppIcon-29@2x~ipad.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "AppIcon-40~ipad.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40"
    },
    {
      "filename" : "AppIcon-40@2x~ipad.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "AppIcon~ipad.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76"
    },
    {
      "filename" : "AppIcon@2x~ipad.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "filename" : "AppIcon-83.5@2x~ipad.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "AppIcon~ios-marketing.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""

        } else {
            // no icon specified
            Assets_xcassets_AppIcon_Contents = """
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
        }

        try Assets_xcassets_AppIcon_Contents.write(to: appProject.darwinAppIconContents.createParentDirectory(), atomically: false, encoding: .utf8)

        // Sources/ModuleName/Resources/Module.xcassets/Contents.json
        try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

""".write(to: appProject.darwinModuleAssetsFolderContents.createParentDirectory(), atomically: false, encoding: .utf8)

        func createXcodeProj() -> String {
            // the .xcodeproj file is located in the Darwin/ folder
            let skipGradleLaunchScript = """
if [ "${SKIP_ZERO}" != "" ]; then
  echo "note: skipping skip due to SKIP_ZERO"
  exit 0
elif [ "${ENABLE_PREVIEWS}" = "YES" ]; then
  echo "note: skipping skip due to ENABLE_PREVIEWS"
  exit 0
elif [ "${ACTION}" = "install" ]; then
  echo "note: skipping skip due to archive install"
  exit 0
elif [ "${SKIP_ACTION}" = "none" ]; then
  echo "note: skipping skip due to SKIP_ACTION none"
  exit 0
else
  SKIP_ACTION="${SKIP_ACTION:-launch}"
fi
PATH=${BUILD_ROOT}/Release:${BUILD_ROOT}/Debug:${BUILD_ROOT}/../../SourcePackages/artifacts/skip/skip/skip.artifactbundle/macos:${PATH}:${HOMEBREW_PREFIX:-/opt/homebrew}/bin
echo "note: running gradle build with: $(which skip) gradle -p ${PWD}/../Android ${SKIP_ACTION:-launch}${CONFIGURATION:-Debug}"
skip gradle -p ../Android ${SKIP_ACTION:-launch}${CONFIGURATION:-Debug}

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
        491F27822DA55B72004926EE /* \(APP_PRODUCT) in Frameworks */ = {isa = PBXBuildFile; productRef = 491F27812DA55B72004926EE /* \(APP_PRODUCT) */; };
        491F27832DA55B72004926EE /* \(APP_PRODUCT) in Embed Frameworks */ = {isa = PBXBuildFile; productRef = 491F27812DA55B72004926EE /* \(APP_PRODUCT) */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };
        496BDBEE2B8A7E9C00C09264 /* Localizable.xcstrings in Resources */ = {isa = PBXBuildFile; fileRef = 496BDBED2B8A7E9C00C09264 /* Localizable.xcstrings */; };
        499CD43B2AC5B799001AE8D8 /* Main.swift in Sources */ = {isa = PBXBuildFile; fileRef = 49F90C2B2A52156200F06D93 /* Main.swift */; };
        499CD4402AC5B799001AE8D8 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = 49F90C2F2A52156300F06D93 /* Assets.xcassets */; };
/* End PBXBuildFile section */

/* Begin PBXCopyFilesBuildPhase section */
        499CD44A2AC5B9C6001AE8D8 /* Embed Frameworks */ = {
            isa = PBXCopyFilesBuildPhase;
            buildActionMask = 2147483647;
            dstPath = "";
            dstSubfolderSpec = 10;
            files = (
                491F27832DA55B72004926EE /* \(APP_PRODUCT) in Embed Frameworks */,
            );
            name = "Embed Frameworks";
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
        4900101C2BACEA710000DE33 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist; path = Info.plist; sourceTree = "<group>"; };
        493609562A6B7EAE00C401E2 /* \(APP_NAME) */ = {isa = PBXFileReference; lastKnownFileType = wrapper; name = \(APP_NAME); path = ..; sourceTree = "<group>"; };
        496BDBEB2B89A47800C09264 /* \(APP_NAME).app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = \(APP_NAME).app; sourceTree = BUILT_PRODUCTS_DIR; };
        496BDBED2B8A7E9C00C09264 /* Localizable.xcstrings */ = {isa = PBXFileReference; lastKnownFileType = text.json.xcstrings; name = Localizable.xcstrings; path = ../Sources/\(APP_NAME)/Resources/Localizable.xcstrings; sourceTree = "<group>"; };
        496EB72F2A6AE4DE00C1253A /* Skip.env */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; name = Skip.env; path = ../Skip.env; sourceTree = "<group>"; };
        496EB72F2A6AE4DE00C1253B /* \(APP_NAME).xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = \(APP_NAME).xcconfig; sourceTree = "<group>"; };
        496EB72F2A6AE4DE00C1253C /* README.md */ = {isa = PBXFileReference; lastKnownFileType = net.daringfireball.markdown; name = README.md; path = ../README.md; sourceTree = "<group>"; };
        499AB9082B0581F4005E8330 /* plugins */ = {isa = PBXFileReference; lastKnownFileType = folder; name = plugins; path = ../../Intermediates.noindex/BuildToolPluginIntermediates; sourceTree = BUILT_PRODUCTS_DIR; };
        49F90C2B2A52156200F06D93 /* Main.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = Main.swift; path = Sources/Main.swift; sourceTree = SOURCE_ROOT; };
        49F90C2F2A52156300F06D93 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
        49F90C312A52156300F06D93 /* Entitlements.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Entitlements.plist; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
        499CD43C2AC5B799001AE8D8 /* Frameworks */ = {
            isa = PBXFrameworksBuildPhase;
            buildActionMask = 2147483647;
            files = (
                491F27822DA55B72004926EE /* \(APP_PRODUCT) in Frameworks */,
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
        496BDBEC2B89A47800C09264 /* Products */ = {
            isa = PBXGroup;
            children = (
                496BDBEB2B89A47800C09264 /* \(APP_NAME).app */,
            );
            name = Products;
            sourceTree = "<group>";
        };
        49AB54462B066A7E007B79B2 /* SkipStone */ = {
            isa = PBXGroup;
            children = (
                499AB9082B0581F4005E8330 /* plugins */,
            );
            name = SkipStone;
            sourceTree = "<group>";
        };
        49F90C1F2A52156200F06D93 = {
            isa = PBXGroup;
            children = (
                496EB72F2A6AE4DE00C1253C /* README.md */,
                496EB72F2A6AE4DE00C1253A /* Skip.env */,
                496EB72F2A6AE4DE00C1253B /* \(APP_NAME).xcconfig */,
                496BDBED2B8A7E9C00C09264 /* Localizable.xcstrings */,
                493609562A6B7EAE00C401E2 /* \(APP_NAME) */,
                49F90C2A2A52156200F06D93 /* App */,
                49AB54462B066A7E007B79B2 /* SkipStone */,
                496BDBEC2B89A47800C09264 /* Products */,
            );
            sourceTree = "<group>";
        };
        49F90C2A2A52156200F06D93 /* App */ = {
            isa = PBXGroup;
            children = (
                49F90C2B2A52156200F06D93 /* Main.swift */,
                49F90C2F2A52156300F06D93 /* Assets.xcassets */,
                49F90C312A52156300F06D93 /* Entitlements.plist */,
                4900101C2BACEA710000DE33 /* Info.plist */,
            );
            name = App;
            sourceTree = "<group>";
        };
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
        499CD4382AC5B799001AE8D8 /* \(APP_TARGET) */ = {
            isa = PBXNativeTarget;
            buildConfigurationList = 499CD4412AC5B799001AE8D8 /* Build configuration list for PBXNativeTarget "\(APP_TARGET)" */;
            buildPhases = (
                499CD43A2AC5B799001AE8D8 /* Sources */,
                499CD43C2AC5B799001AE8D8 /* Frameworks */,
                499CD43E2AC5B799001AE8D8 /* Resources */,
                499CD4452AC5B869001AE8D8 /* Run skip gradle */,
                499CD44A2AC5B9C6001AE8D8 /* Embed Frameworks */,
            );
            buildRules = (
            );
            dependencies = (
            );
            name = "\(APP_TARGET)";
            packageProductDependencies = (
                491F27812DA55B72004926EE /* \(APP_PRODUCT) */,
            );
            productName = App;
            productReference = 496BDBEB2B89A47800C09264 /* \(APP_NAME).app */;
            productType = "com.apple.product-type.application";
        };
/* End PBXNativeTarget section */

/* Begin PBXProject section */
        49F90C202A52156200F06D93 /* Project object */ = {
            isa = PBXProject;
            attributes = {
                BuildIndependentTargetsInParallel = 1;
                LastSwiftUpdateCheck = 1430;
                LastUpgradeCheck = 1630;
            };
            buildConfigurationList = 49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(APP_NAME)" */;
            compatibilityVersion = "Xcode 14.0";
            developmentRegion = en;
            hasScannedForEncodings = 0;
            knownRegions = (
                en,
                Base,
                es,
                ja,
                "zh-Hans",
            );
            mainGroup = 49F90C1F2A52156200F06D93;
            packageReferences = (
            );
            productRefGroup = 496BDBEC2B89A47800C09264 /* Products */;
            projectDirPath = "";
            projectRoot = "";
            targets = (
                499CD4382AC5B799001AE8D8 /* \(APP_TARGET) */,
            );
        };
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
        499CD43E2AC5B799001AE8D8 /* Resources */ = {
            isa = PBXResourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
                499CD4402AC5B799001AE8D8 /* Assets.xcassets in Resources */,
                496BDBEE2B8A7E9C00C09264 /* Localizable.xcstrings in Resources */,
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXResourcesBuildPhase section */

/* Begin PBXShellScriptBuildPhase section */
        499CD4452AC5B869001AE8D8 /* Run skip gradle */ = {
            isa = PBXShellScriptBuildPhase;
            alwaysOutOfDate = 1;
            buildActionMask = 2147483647;
            files = (
            );
            inputFileListPaths = (
            );
            inputPaths = (
            );
            name = "Run skip gradle";
            outputFileListPaths = (
            );
            outputPaths = (
            );
            runOnlyForDeploymentPostprocessing = 0;
            shellPath = "/bin/sh -e";
            shellScript = "\(skipGradleLaunchScript)";
        };
/* End PBXShellScriptBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
        499CD43A2AC5B799001AE8D8 /* Sources */ = {
            isa = PBXSourcesBuildPhase;
            buildActionMask = 2147483647;
            files = (
                499CD43B2AC5B799001AE8D8 /* Main.swift in Sources */,
            );
            runOnlyForDeploymentPostprocessing = 0;
        };
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
        499CD4422AC5B799001AE8D8 /* Debug */ = {
            isa = XCBuildConfiguration;
            baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(APP_NAME).xcconfig */;
            buildSettings = {
                ENABLE_PREVIEWS = YES;
                LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
            };
            name = Debug;
        };
        499CD4432AC5B799001AE8D8 /* Release */ = {
            isa = XCBuildConfiguration;
            baseConfigurationReference = 496EB72F2A6AE4DE00C1253B /* \(APP_NAME).xcconfig */;
            buildSettings = {
                ENABLE_PREVIEWS = YES;
                LD_RUNPATH_SEARCH_PATHS = "@executable_path/Frameworks";
                "LD_RUNPATH_SEARCH_PATHS[sdk=macosx*]" = "@executable_path/../Frameworks";
            };
            name = Release;
        };
        49F90C4B2A52156300F06D93 /* Debug */ = {
            isa = XCBuildConfiguration;
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
            buildSettings = {
                ALWAYS_SEARCH_USER_PATHS = NO;
                ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
                COPY_PHASE_STRIP = NO;
                DEBUG_INFORMATION_FORMAT = dwarf-with-dsym;
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
        499CD4412AC5B799001AE8D8 /* Build configuration list for PBXNativeTarget "\(APP_TARGET)" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                499CD4422AC5B799001AE8D8 /* Debug */,
                499CD4432AC5B799001AE8D8 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
        49F90C232A52156200F06D93 /* Build configuration list for PBXProject "\(APP_NAME)" */ = {
            isa = XCConfigurationList;
            buildConfigurations = (
                49F90C4B2A52156300F06D93 /* Debug */,
                49F90C4C2A52156300F06D93 /* Release */,
            );
            defaultConfigurationIsVisible = 0;
            defaultConfigurationName = Release;
        };
/* End XCConfigurationList section */

/* Begin XCSwiftPackageProductDependency section */
        491F27812DA55B72004926EE /* \(APP_PRODUCT) */ = {
            isa = XCSwiftPackageProductDependency;
            productName = \(APP_PRODUCT);
        };
/* End XCSwiftPackageProductDependency section */
    };
    rootObject = 49F90C202A52156200F06D93 /* Project object */;
}

"""
        }

        let xcodeProjectContents = createXcodeProj()
        let xcodeProjectPbxprojURL = appProject.darwinProjectContents
        // change spaces to tabs in the pbxproj, since that is what Xcode will do when it saves it
        try xcodeProjectContents.replacingOccurrences(of: "    ", with: "\t").write(to: xcodeProjectPbxprojURL, atomically: false, encoding: .utf8)


        let xcschemeContents = """
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1630"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "499CD4382AC5B799001AE8D8"
               BuildableName = "\(APP_NAME).app"
               BlueprintName = "\(APP_TARGET)"
               ReferencedContainer = "container:\(APP_NAME).xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "499CD4382AC5B799001AE8D8"
            BuildableName = "\(APP_NAME).app"
            BlueprintName = "\(APP_TARGET)"
            ReferencedContainer = "container:\(APP_NAME).xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "499CD4382AC5B799001AE8D8"
            BuildableName = "\(APP_NAME).app"
            BlueprintName = "\(APP_TARGET)"
            ReferencedContainer = "container:\(APP_NAME).xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>

"""

        let xcodeProjectSchemeURL = appProject.darwinSchemesFolder.appending(path: "\(APP_TARGET).xcscheme")
        try xcschemeContents.write(to: xcodeProjectSchemeURL.createParentDirectory(), atomically: false, encoding: .utf8)

        let workspaceData = """
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:Darwin/\(APP_NAME).xcodeproj">
   </FileRef>
</Workspace>
"""
        try workspaceData.write(to: appProject.workspaceContents.createParentDirectory(), atomically: false, encoding: .utf8)

        let androidIconName: String? = hasIcon ? "mipmap/ic_launcher" : nil
        try createAndroidManifest(androidIconName: androidIconName).write(to: appProject.androidManifest.createParentDirectory(), atomically: false, encoding: .utf8)
        try createSettingsGradle().write(to: appProject.androidGradleSettings, atomically: false, encoding: .utf8)
        try createAppBuildGradle(appModulePackage: appModulePackage, appModuleName: appModuleName).write(to: appProject.androidAppBuildGradle, atomically: false, encoding: .utf8)
        try defaultProguardContents(appModulePackage).write(to: appProject.androidAppProguardRules, atomically: false, encoding: .utf8)
        try defaultGradleProperties().write(to: appProject.androidGradleProperties, atomically: false, encoding: .utf8)
        try defaultGradleWrapperProperties().write(to: appProject.androidGradleWrapperProperties.createParentDirectory(), atomically: false, encoding: .utf8)


        let sourceMainKotlinPackage = appProject.androidAppSrcMainKotlin
        let sourceMainKotlinSourceFile = sourceMainKotlinPackage.appendingPathComponent("Main.kt")
        try createKotlinMain(appModulePackage: appModulePackage, appModuleName: appModuleName, nativeLibrary: nativeMode.contains(.nativeModel) ? secondModule?.moduleName : nil).write(to: sourceMainKotlinSourceFile.createParentDirectory(), atomically: false, encoding: .utf8)

        return (projectURL, appProject)
    }
}


extension FrameworkProjectLayout {
    static func createAndroidManifest(androidIconName: String?) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <!-- This AndroidManifest.xml template was generated by Skip -->
        <manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">
            <!-- example permissions for using device location -->
            <!-- <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/> -->
            <!-- <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/> -->

            <!-- permissions needed for using the internet or an embedded WebKit browser -->
            <uses-permission android:name="android.permission.INTERNET" />
            <!-- <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" /> -->

            <application
                android:label="${PRODUCT_NAME}"
                android:name=".AndroidAppMain"
                android:supportsRtl="true"
                android:allowBackup="true"
                \(androidIconName != nil ? "android:icon=\"@\(androidIconName!)\"" : "")>
                <activity
                    android:name=".MainActivity"
                    android:exported="true"
                    android:configChanges="orientation|screenSize|screenLayout|keyboardHidden|mnc|colorMode|density|fontScale|fontWeightAdjustment|keyboard|layoutDirection|locale|mcc|navigation|smallestScreenSize|touchscreen|uiMode"
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
    }

    static func createSettingsGradle() -> String {
        """
        // This gradle project is part of a conventional Skip app project.
        pluginManagement {
            // Initialize the Skip plugin folder and perform a pre-build for non-Xcode builds
            val pluginPath = File.createTempFile("skip-plugin-path", ".tmp")

            // overriding outputs for an Android IDE can be done by un-commenting and setting the Xcode path:
            //System.setProperty("BUILT_PRODUCTS_DIR", "${System.getProperty("user.home")}/Library/Developer/Xcode/DerivedData/MySkipProject-HASH/Build/Products/Debug-iphonesimulator")

            val skipPluginResult = providers.exec {
                commandLine("/bin/sh", "-c", "skip plugin --prebuild --package-path '${settings.rootDir.parent}' --plugin-ref '${pluginPath.absolutePath}'")
                environment("PATH", "${System.getenv("PATH")}:/opt/homebrew/bin")
            }
            val skipPluginOutput = skipPluginResult.standardOutput.asText.get()
            print(skipPluginOutput)
            val skipPluginError = skipPluginResult.standardError.asText.get()
            print(skipPluginError)

            includeBuild(pluginPath.readText()) {
                name = "skip-plugins"
            }
        }

        plugins {
            id("skip-plugin") apply true
        }

        """
    }


    static func createAppBuildGradle(appModulePackage: String, appModuleName: String) -> String {
        """
        import java.util.Properties

        plugins {
            alias(libs.plugins.kotlin.android)
            alias(libs.plugins.kotlin.compose)
            alias(libs.plugins.android.application)
            id("skip-build-plugin")
        }

        skip {
        }

        kotlin {
            compilerOptions {
                jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(libs.versions.jvm.get().toString())
            }
        }

        android {
            namespace = group as String
            compileSdk = libs.versions.android.sdk.compile.get().toInt()
            compileOptions {
                sourceCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
                targetCompatibility = JavaVersion.toVersion(libs.versions.jvm.get())
            }
            packaging {
                jniLibs {
                    keepDebugSymbols.add("**/*.so")
                    pickFirsts.add("**/*.so")
                    // this option will compress JNI .so files
                    useLegacyPackaging = true
                }
            }

            defaultConfig {
                minSdk = libs.versions.android.sdk.min.get().toInt()
                targetSdk = libs.versions.android.sdk.compile.get().toInt()
                // skip.tools.skip-build-plugin will automatically use Skip.env properties for:
                // applicationId = ANDROID_APPLICATION_ID ?? PRODUCT_BUNDLE_IDENTIFIER
                // versionCode = CURRENT_PROJECT_VERSION
                // versionName = MARKETING_VERSION
            }

            buildFeatures {
                buildConfig = true
            }

            lint {
                disable.add("Instantiatable")
                disable.add("MissingPermission")
            }

            dependenciesInfo {
                // Disables dependency metadata when building APKs.
                includeInApk = false
                // Disables dependency metadata when building Android App Bundles.
                includeInBundle = false
            }

            // default signing configuration tries to load from keystore.properties
            // see: https://skip.dev/docs/deployment/#export-signing
            signingConfigs {
                val keystorePropertiesFile = file("keystore.properties")
                create("release") {
                    if (keystorePropertiesFile.isFile) {
                        val keystoreProperties = Properties()
                        keystoreProperties.load(keystorePropertiesFile.inputStream())
                        keyAlias = keystoreProperties.getProperty("keyAlias")
                        keyPassword = keystoreProperties.getProperty("keyPassword")
                        storeFile = file(keystoreProperties.getProperty("storeFile"))
                        storePassword = keystoreProperties.getProperty("storePassword")
                    } else {
                        // when there is no keystore.properties file, fall back to signing with debug config
                        keyAlias = signingConfigs.getByName("debug").keyAlias
                        keyPassword = signingConfigs.getByName("debug").keyPassword
                        storeFile = signingConfigs.getByName("debug").storeFile
                        storePassword = signingConfigs.getByName("debug").storePassword
                    }
                }
            }

            buildTypes {
                release {
                    signingConfig = signingConfigs.findByName("release")
                    isMinifyEnabled = true
                    isShrinkResources = true
                    isDebuggable = false // can be set to true for debugging release build, but needs to be false when uploading to store
                    proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
                }
            }
        }

        """
    }

    static func createKotlinMain(appModulePackage: String, appModuleName: String, nativeLibrary: String?) -> String {
"""
package \(appModulePackage)

import skip.lib.*
import skip.model.*
import skip.foundation.*
import skip.ui.*

import android.Manifest
import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.SystemBarStyle
import androidx.activity.ComponentActivity
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.material3.MaterialTheme
import androidx.core.app.ActivityCompat

internal val logger: SkipLogger = SkipLogger(subsystem = "\(appModulePackage)", category = "\(appModuleName)")

private typealias AppRootView = \(appModuleName)RootView
private typealias AppDelegate = \(appModuleName)AppDelegate

/// AndroidAppMain is the `android.app.Application` entry point, and must match `application android:name` in the AndroidMainfest.xml file.
open class AndroidAppMain: Application {
    constructor() {
    }

    override fun onCreate() {
        super.onCreate()
        logger.info("starting app")
        ProcessInfo.launch(applicationContext)
        AppDelegate.shared.onInit()
    }

    companion object {
    }
}

/// AndroidAppMain is initial `androidx.appcompat.app.AppCompatActivity`, and must match `activity android:name` in the AndroidMainfest.xml file.
open class MainActivity: AppCompatActivity {
    constructor() {
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        logger.info("starting activity")
        UIApplication.launch(this)
        enableEdgeToEdge()

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }

        AppDelegate.shared.onLaunch()

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

    override fun onStart() {
        logger.info("onStart")
        super.onStart()
    }

    override fun onResume() {
        super.onResume()
        AppDelegate.shared.onResume()
    }

    override fun onPause() {
        super.onPause()
        AppDelegate.shared.onPause()
    }

    override fun onStop() {
        super.onStop()
        AppDelegate.shared.onStop()
    }

    override fun onDestroy() {
        super.onDestroy()
        AppDelegate.shared.onDestroy()
    }

    override fun onLowMemory() {
        super.onLowMemory()
        AppDelegate.shared.onLowMemory()
    }

    override fun onRestart() {
        logger.info("onRestart")
        super.onRestart()
    }

    override fun onSaveInstanceState(outState: android.os.Bundle): Unit = super.onSaveInstanceState(outState)

    override fun onRestoreInstanceState(bundle: android.os.Bundle) {
        // Usually you restore your state in onCreate(). It is possible to restore it in onRestoreInstanceState() as well, but not very common. (onRestoreInstanceState() is called after onStart(), whereas onCreate() is called before onStart().
        logger.info("onRestoreInstanceState")
        super.onRestoreInstanceState(bundle)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: kotlin.Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        logger.info("onRequestPermissionsResult: ${requestCode}")
    }

    companion object {
    }
}

@Composable
internal fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f

    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }

    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(
            statusBarStyle = style,
            navigationBarStyle = style
        )
        onDispose { }
    }
}

@Composable
internal fun PresentationRootView(context: ComposeContext) {
    val colorScheme = if (isSystemInDarkTheme()) ColorScheme.dark else ColorScheme.light
    PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
        SyncSystemBarsWithTheme()
        val contentContext = ctx.content()
        Box(modifier = ctx.modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AppRootView().Compose(context = contentContext)
        }
    }
}

"""
    }

    /// See https://github.com/skiptools/skip/issues/95 for why we need to be so permissive
    static func defaultProguardContents(_ packageName: String) -> String {
        // com.sun.jna.Pointer needed since the field pointer name is looked up by reflection
        // keeppackagenames is needed because Bundle.module might not be found otherwise
        """
        -keeppackagenames **
        -keep class skip.** { *; }
        -keep class tools.skip.** { *; }
        -keep class kotlin.jvm.functions.** {*;}
        -keep class com.sun.jna.** { *; }
        -dontwarn java.awt.**
        -keep class * implements com.sun.jna.** { *; }
        -keep class * implements skip.bridge.** { *; }
        -keep class **._ModuleBundleAccessor_* { *; }
        -keep class \(packageName).** { *; }

        """
    }

    static func defaultGradleProperties() -> String {
        """
        org.gradle.jvmargs=-Xmx4g
        android.useAndroidX=true
        kotlin.code.style=official

        """
    }

    /// the Gradle version string to generate
    static let gradleVersion = "9.0.0"

    static func defaultGradleWrapperProperties() -> String {
        """
        distributionUrl=https\\://services.gradle.org/distributions/gradle-\(gradleVersion)-bin.zip

        """
    }
}

// cat SkipLogo.pdf | base64 -b 80 -i - | pbcopy
// not currently used, but we might populate the Module.xcassets catalog with it,
// and use it as the basis for
fileprivate let logoPDF = """
JVBERi0xLjMKJcTl8uXrp/Og0MTGCjMgMCBvYmoKPDwgL0ZpbHRlciAvRmxhdGVEZWNvZGUgL0xlbmd0
aCAxMTQ5ID4+CnN0cmVhbQp4AXWVW2pmNxCE388qtAKlb2q1nrOCPGUBJmECdmDi/UO+lj0mkIRh4Lh+
Xbqrq0rfxy/j+9Al05buYbZnpa/xNkxzmngN3TaP6BqvYDVXHAWT6SeDDTq1ZA3NmrqXP2YxZZ0NktMj
a7wMc5mauzGbsZKLfE8r56TkajdOipg7lPtARCsf9sWep5LT15nHUgdVTjv73FW6WW4rZmp9IHVO9H07
58d1a7JGHzsyM92G1p6rOKcWjVKRyZnbVXtXY3bWB6bl3THYkXOhBh49OXdu6q2Y6vDzChsxow9zMQ6z
5kenb7pyzyklIHVmHZj1VTP20W5PuHDBou89Ny00w0ENClQ1M8zvSCJPDj9ruvfNoTMiHYQ2wy5Ta81Q
mPIDZatX5ZlytFf53MLNtm8JytlQdjTp2WF9bSkKFUqw/byC5Sw/Z7jVdIoGOdOpwJBE9uJlU3XxA8OO
YticRF/WSnCTuZzdSUln5+OohrvZv31KBttApOL0NkZlexsYhZ/icMpcQZW97X6UzUJbFzlZB+pC4GkJ
24zuKmIgnV7VxS5GLA6CEvfixIReiVZiY0j1QgVf3S5dhawcEQJ1tRmDC3qJZSNasL4gD30L9Y3ADisK
gh3BGqZhOojauiwT5p7rgCF+RzGtBKzEKjxGaygBMkuRWUDekssCQmolsApJ8BtloZdE8k22zr3VBpNl
dZuOEjAeR/3Lty/j2/h1/DmEf4s9/H/++u0Dmjn+GD/9/I7W3weuy1VmxtcKjIvmZJZUcvJ4fxmtv3t/
MLXb8NsT2qXD8Rf2CqOfmCKA61Fq/7H3H9i38fvNGl975tp4Eiuicu+swZ7on2k65nB8+uE83IMTAsIP
cgTbSMKSdQSDCqpple/VIoNVJNAIUyzpfdTjyIaxUNqu1isY3Hdq5MR5WBaEahgwOeLLNyf1pFE5+1w5
i3F6OFNsV6HSskY6+AxRQ+FMRGOHOxI5sA1o2zJipzHihtJ7WfY9YFnVcerqGNnb4xQvDBSMwFjaiaOM
vTjYP2QZj9J9tsWRvC9YUEyP1btDl45f2ldfHM+PXHmQUCrJ2C49MNGUW2U+ShsuWNoYLs4ldRW3Ooub
LaqBdTAmv4g4u5ZiPr2PNwKWEX+g2keNiG07vBDJeEvv69DtZFKDpiOK1YnYrr5TVLg3BqRkK1lMfQQO
WaaPIpySTktY0N0PBgivh/fxeAQD8hiA6U18xlPCNDvViySkU1rW2JxEg90MKiFF4BhtNLHYiBAqYuc+
IYEQ2lgnhctQn6zLJ0MSYqUr6a9zcKSiUq49o+MklfyEY8WKZNLAiSRlP2yMnNTA3UiR8Gf+/Q2tJMHW
0Kd/IfDJc3LC7juBBIqyNnGN0jTsytZ5gl3QGGpPMZrobCvl2YTq3f59nDuUaDu8Cd7PJ1ooQsjutPgg
q6mTl4SjmlnWh9x0RJCHvO7h+pbz/HDmlcl15n+kyfifNOGFFp41MiQxEXJ8pDWARE+nybFP0h2irk/f
qAnHdU1fWNf5iUH969cugoe/boL8DRQHuCQKZW5kc3RyZWFtCmVuZG9iagoxIDAgb2JqCjw8IC9UeXBl
IC9QYWdlIC9QYXJlbnQgMiAwIFIgL1Jlc291cmNlcyA0IDAgUiAvQ29udGVudHMgMyAwIFIgPj4KZW5k
b2JqCjQgMCBvYmoKPDwgL1Byb2NTZXQgWyAvUERGIF0gL0NvbG9yU3BhY2UgPDwgL0NzMSA1IDAgUiA+
PiA+PgplbmRvYmoKNiAwIG9iago8PCAvTiAzIC9BbHRlcm5hdGUgL0RldmljZVJHQiAvTGVuZ3RoIDI2
MTIgL0ZpbHRlciAvRmxhdGVEZWNvZGUgPj4Kc3RyZWFtCngBnZZ3VFPZFofPvTe90BIiICX0GnoJINI7
SBUEUYlJgFAChoQmdkQFRhQRKVZkVMABR4ciY0UUC4OCYtcJ8hBQxsFRREXl3YxrCe+tNfPemv3HWd/Z
57fX2Wfvfde6AFD8ggTCdFgBgDShWBTu68FcEhPLxPcCGBABDlgBwOFmZgRH+EQC1Py9PZmZqEjGs/bu
LoBku9ssv1Amc9b/f5EiN0MkBgAKRdU2PH4mF+UClFOzxRky/wTK9JUpMoYxMhahCaKsIuPEr2z2p+Yr
u8mYlybkoRpZzhm8NJ6Mu1DemiXho4wEoVyYJeBno3wHZb1USZoA5fco09P4nEwAMBSZX8znJqFsiTJF
FBnuifICAAiUxDm8cg6L+TlongB4pmfkigSJSWKmEdeYaeXoyGb68bNT+WIxK5TDTeGIeEzP9LQMjjAX
gK9vlkUBJVltmWiR7a0c7e1Z1uZo+b/Z3x5+U/09yHr7VfEm7M+eQYyeWd9s7KwvvRYA9iRamx2zvpVV
ALRtBkDl4axP7yAA8gUAtN6c8x6GbF6SxOIMJwuL7OxscwGfay4r6Df7n4Jvyr+GOfeZy+77VjumFz+B
I0kVM2VF5aanpktEzMwMDpfPZP33EP/jwDlpzcnDLJyfwBfxhehVUeiUCYSJaLuFPIFYkC5kCoR/1eF/
GDYnBxl+nWsUaHVfAH2FOVC4SQfIbz0AQyMDJG4/egJ961sQMQrIvrxorZGvc48yev7n+h8LXIpu4UxB
IlPm9gyPZHIloiwZo9+EbMECEpAHdKAKNIEuMAIsYA0cgDNwA94gAISASBADlgMuSAJpQASyQT7YAApB
MdgBdoNqcADUgXrQBE6CNnAGXARXwA1wCwyAR0AKhsFLMAHegWkIgvAQFaJBqpAWpA+ZQtYQG1oIeUNB
UDgUA8VDiZAQkkD50CaoGCqDqqFDUD30I3Qaughdg/qgB9AgNAb9AX2EEZgC02EN2AC2gNmwOxwIR8LL
4ER4FZwHF8Db4Uq4Fj4Ot8IX4RvwACyFX8KTCEDICAPRRlgIG/FEQpBYJAERIWuRIqQCqUWakA6kG7mN
SJFx5AMGh6FhmBgWxhnjh1mM4WJWYdZiSjDVmGOYVkwX5jZmEDOB+YKlYtWxplgnrD92CTYRm40txFZg
j2BbsJexA9hh7DscDsfAGeIccH64GFwybjWuBLcP14y7gOvDDeEm8Xi8Kt4U74IPwXPwYnwhvgp/HH8e
348fxr8nkAlaBGuCDyGWICRsJFQQGgjnCP2EEcI0UYGoT3QihhB5xFxiKbGO2EG8SRwmTpMUSYYkF1Ik
KZm0gVRJaiJdJj0mvSGTyTpkR3IYWUBeT64knyBfJQ+SP1CUKCYUT0ocRULZTjlKuUB5QHlDpVINqG7U
WKqYup1aT71EfUp9L0eTM5fzl+PJrZOrkWuV65d7JU+U15d3l18unydfIX9K/qb8uAJRwUDBU4GjsFah
RuG0wj2FSUWaopViiGKaYolig+I1xVElvJKBkrcST6lA6bDSJaUhGkLTpXnSuLRNtDraZdowHUc3pPvT
k+nF9B/ovfQJZSVlW+Uo5RzlGuWzylIGwjBg+DNSGaWMk4y7jI/zNOa5z+PP2zavaV7/vCmV+SpuKnyV
IpVmlQGVj6pMVW/VFNWdqm2qT9QwaiZqYWrZavvVLquNz6fPd57PnV80/+T8h+qwuol6uPpq9cPqPeqT
GpoavhoZGlUalzTGNRmabprJmuWa5zTHtGhaC7UEWuVa57VeMJWZ7sxUZiWzizmhra7tpy3RPqTdqz2t
Y6izWGejTrPOE12SLls3Qbdct1N3Qk9LL1gvX69R76E+UZ+tn6S/R79bf8rA0CDaYItBm8GooYqhv2Ge
YaPhYyOqkavRKqNaozvGOGO2cYrxPuNbJrCJnUmSSY3JTVPY1N5UYLrPtM8Ma+ZoJjSrNbvHorDcWVms
RtagOcM8yHyjeZv5Kws9i1iLnRbdFl8s7SxTLessH1kpWQVYbbTqsPrD2sSaa11jfceGauNjs86m3ea1
rakt33a/7X07ml2w3Ra7TrvP9g72Ivsm+zEHPYd4h70O99h0dii7hH3VEevo4bjO8YzjByd7J7HTSaff
nVnOKc4NzqMLDBfwF9QtGHLRceG4HHKRLmQujF94cKHUVduV41rr+sxN143ndsRtxN3YPdn9uPsrD0sP
kUeLx5Snk+cazwteiJevV5FXr7eS92Lvau+nPjo+iT6NPhO+dr6rfS/4Yf0C/Xb63fPX8Of61/tPBDgE
rAnoCqQERgRWBz4LMgkSBXUEw8EBwbuCHy/SXyRc1BYCQvxDdoU8CTUMXRX6cxguLDSsJux5uFV4fnh3
BC1iRURDxLtIj8jSyEeLjRZLFndGyUfFRdVHTUV7RZdFS5dYLFmz5EaMWowgpj0WHxsVeyR2cqn30t1L
h+Ps4grj7i4zXJaz7NpyteWpy8+ukF/BWXEqHhsfHd8Q/4kTwqnlTK70X7l35QTXk7uH+5LnxivnjfFd
+GX8kQSXhLKE0USXxF2JY0muSRVJ4wJPQbXgdbJf8oHkqZSQlKMpM6nRqc1phLT4tNNCJWGKsCtdMz0n
vS/DNKMwQ7rKadXuVROiQNGRTChzWWa7mI7+TPVIjCSbJYNZC7Nqst5nR2WfylHMEeb05JrkbssdyfPJ
+341ZjV3dWe+dv6G/ME17msOrYXWrlzbuU53XcG64fW+649tIG1I2fDLRsuNZRvfbore1FGgUbC+YGiz
7+bGQrlCUeG9Lc5bDmzFbBVs7d1ms61q25ciXtH1YsviiuJPJdyS699ZfVf53cz2hO29pfal+3fgdgh3
3N3puvNYmWJZXtnQruBdreXM8qLyt7tX7L5WYVtxYA9pj2SPtDKosr1Kr2pH1afqpOqBGo+a5r3qe7ft
ndrH29e/321/0wGNA8UHPh4UHLx/yPdQa61BbcVh3OGsw8/rouq6v2d/X39E7Ujxkc9HhUelx8KPddU7
1Nc3qDeUNsKNksax43HHb/3g9UN7E6vpUDOjufgEOCE58eLH+B/vngw82XmKfarpJ/2f9rbQWopaodbc
1om2pDZpe0x73+mA050dzh0tP5v/fPSM9pmas8pnS8+RzhWcmzmfd37yQsaF8YuJF4c6V3Q+urTk0p2u
sK7ey4GXr17xuXKp2737/FWXq2euOV07fZ19ve2G/Y3WHruell/sfmnpte9tvelws/2W462OvgV95/pd
+y/e9rp95Y7/nRsDiwb67i6+e/9e3D3pfd790QepD14/zHo4/Wj9Y+zjoicKTyqeqj+t/dX412apvfTs
oNdgz7OIZ4+GuEMv/5X5r0/DBc+pzytGtEbqR61Hz4z5jN16sfTF8MuMl9Pjhb8p/rb3ldGrn353+71n
YsnE8GvR65k/St6ovjn61vZt52To5NN3ae+mp4req74/9oH9oftj9MeR6exP+E+Vn40/d3wJ/PJ4Jm1m
5t/3hPP7CmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iagpbIC9JQ0NCYXNlZCA2IDAgUiBdCmVuZG9iagoy
IDAgb2JqCjw8IC9UeXBlIC9QYWdlcyAvTWVkaWFCb3ggWzAgMCA1MTIgNTEyXSAvQ291bnQgMSAvS2lk
cyBbIDEgMCBSIF0gPj4KZW5kb2JqCjcgMCBvYmoKPDwgL1R5cGUgL0NhdGFsb2cgL1BhZ2VzIDIgMCBS
ID4+CmVuZG9iago4IDAgb2JqCjw8IC9Qcm9kdWNlciAobWFjT1MgVmVyc2lvbiAxNC41IFwoQnVpbGQg
MjNGNzlcKSBRdWFydHogUERGQ29udGV4dCkgL0NyZWF0aW9uRGF0ZQooRDoyMDI0MDYwNTIyMzczOFow
MCcwMCcpIC9Nb2REYXRlIChEOjIwMjQwNjA1MjIzNzM4WjAwJzAwJykgPj4KZW5kb2JqCnhyZWYKMCA5
CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMTI0NCAwMDAwMCBuIAowMDAwMDA0MTM5IDAwMDAwIG4g
CjAwMDAwMDAwMjIgMDAwMDAgbiAKMDAwMDAwMTMyNCAwMDAwMCBuIAowMDAwMDA0MTA0IDAwMDAwIG4g
CjAwMDAwMDEzOTIgMDAwMDAgbiAKMDAwMDAwNDIyMiAwMDAwMCBuIAowMDAwMDA0MjcxIDAwMDAwIG4g
CnRyYWlsZXIKPDwgL1NpemUgOSAvUm9vdCA3IDAgUiAvSW5mbyA4IDAgUiAvSUQgWyA8MWFlODJkYjBm
ODg2YzVkZmI5OTQyZDZjNmE2MjQxODU+CjwxYWU4MmRiMGY4ODZjNWRmYjk5NDJkNmM2YTYyNDE4NT4g
XSA+PgpzdGFydHhyZWYKNDQzMgolJUVPRgo=
"""
