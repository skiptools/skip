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

        // a free app is GPL, a free library is LGPL
        var sourceHeader = options.free ? (SourceLicense.defaultLicense(app: app).sourceHeader + "\n\n") : ""
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
                # Configuration file for Skip (https://skip.dev) project
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

                // only create the transpiled test harness when this is a non-native module or if the module is bridged;
                // otherwise, pure swift testing will suffice for both Darwin and Android
                if !isNativeModule || moduleMode == .nativeBridged {
                    let testSkipModuleFile = testDir.appending(path: "XCSkipTests.swift")
                    try """
                    \(sourceHeader)import Foundation
                    #if os(macOS) || os(Linux) // Skip transpiled tests only run on supported hosts
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
                    
                    /// True when running in a transpiled Java runtime environment
                    let isJava = ProcessInfo.processInfo.environment["java.io.tmpdir"] != nil
                    /// True when running within an Android environment (either an emulator or device)
                    let isAndroid = isJava && ProcessInfo.processInfo.environment["ANDROID_ROOT"] != nil
                    /// True is the transpiled code is currently running in the local Robolectric test environment
                    let isRobolectric = isJava && !isAndroid
                    /// True if the system's `Int` type is 32-bit.
                    let is32BitInteger = Int64(Int.max) == Int64(Int32.max)
                    \(sourceFooter)
                    
                    """.write(to: testSkipModuleFile, atomically: false, encoding: .utf8)
                }

                let skipYamlAppTests = """
                # Configuration file for Skip (https://skip.dev) project
                #build:
                #  contents:
                """

                let skipYamlModuleTests = """
                # Configuration file for Skip (https://skip.dev) project
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

        if options.free {
            if SourceLicense.allCases.first == .osl {
                appREADME += """
                
                ## License

                This software is licensed under the [Open Software License version 3.0](https://opensource.org/license/osl-3-0).

                """
            } else {
                appREADME += """
                
                ## License
                
                This software is licensed under the [GNU General Public License v2.0 or later](https://spdx.org/licenses/GPL-2.0-or-later.html).
                
                """
            }
        }

        try (app ? appREADME : libREADME).write(to: readmeURL, atomically: false, encoding: .utf8)

        if options.free == true {
            let license = SourceLicense.defaultLicense(app: app)
            try license.licenseContents
                .write(to: projectFolderURL.appending(path: license.licenseFilename), atomically: false, encoding: .utf8)
        }

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
        let sourceHeader = options.free ? (SourceLicense.defaultLicense(app: true).sourceHeader + "\n\n") : ""

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
  "alcoholTobaccoOrDrugUseOrReferences": "NONE",
  "contests": "NONE",
  "gamblingSimulated": "NONE",
  "horrorOrFearThemes": "NONE",
  "koreaAgeRatingOverride": "NONE",
  "matureOrSuggestiveThemes": "NONE",
  "medicalOrTreatmentInformation": "NONE",
  "profanityOrCrudeHumor": "NONE",
  "sexualContentGraphicAndNudity": "NONE",
  "sexualContentOrNudity": "NONE",
  "violenceCartoonOrFantasy": "NONE",
  "violenceRealisticProlongedGraphicOrSadistic": "NONE",
  "violenceRealistic": "NONE",
  "gambling": false,
  "lootBox": false,
  "unrestrictedWebAccess": false
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

let useLGPLException = false

enum SourceLicense: Equatable, CaseIterable {
    case lgpl3
    case lgpl3LinkingException
    case gpl2
    case gpl3
    case osl

    static func defaultLicense(app: Bool) -> SourceLicense {
        // if we ever want to switch the default license to OSL, move it to the first entry of the enumeration
        if SourceLicense.allCases.first == .osl {
            return .osl
        } else if app {
            return .gpl3
        } else {
            return .lgpl3LinkingException
        }
    }

    var sourceHeader: String {
        return "// Licensed under the \(self.spdx.name)\n// SPDX-License-Identifier: \(self.spdx.identifier)"
    }

    var spdx: (name: String, identifier: String) {
        switch self {
        case .lgpl3:
            return ("GNU Lesser General Public License v3.0", "LGPL-3.0-only") // https://spdx.org/licenses/LGPL-3.0-only.html
        case .lgpl3LinkingException:
            return ("GNU General Public License v3.0 with Linking Exception", "LGPL-3.0-only WITH LGPL-3.0-linking-exception") // https://spdx.org/licenses/LGPL-3.0-linking-exception.html
        case .gpl2:
            return ("GNU General Public License v2.0 or later", "GPL-2.0-or-later") // https://spdx.org/licenses/GPL-2.0-or-later.html
        case .gpl3:
            return ("GNU General Public License v3.0 or later", "GPL-3.0-or-later") // https://spdx.org/licenses/GPL-3.0-or-later.html
        case .osl:
            return ("Open Software License 3.0", "OSL-3.0") // https://spdx.org/licenses/OSL-3.0.html
        }
    }

    var licenseFilename: String {
        return "LICENSE.txt"
        //switch self {
        //case .lgpl3: return "LICENSE.LGPL"
        //case .lgpl3LinkingException: return "LICENSE.LGPL"
        //case .gpl2: return "LICENSE.GPL"
        //case .gpl3: return "LICENSE.GPL"
        //case .osl: return "LICENSE.txt"
        //}
    }

    var licenseContents: String {
        switch self {
        case .lgpl3: return licenseLGPL3Contents
        case .lgpl3LinkingException: return licenseLGPL3LinkingExceptionContents
        case .gpl2: return licenseGPL2Contents
        case .gpl3: return licenseGPL3Contents
        case .osl: return licenseOSLContents
        }
    }
}


let licenseOSLContents = """
Open Software License ("OSL") v. 3.0

This Open Software License (the "License") applies to any original work of
authorship (the "Original Work") whose owner (the "Licensor") has placed the
following licensing notice adjacent to the copyright notice for the Original
Work:

  Licensed under the Open Software License version 3.0

1) Grant of Copyright License. Licensor grants You a worldwide, royalty-free,
non-exclusive, sublicensable license, for the duration of the copyright, to do
the following:

  a) to reproduce the Original Work in copies, either alone or as part of a
  collective work;

  b) to translate, adapt, alter, transform, modify, or arrange the Original
  Work, thereby creating derivative works ("Derivative Works") based upon the
  Original Work;

  c) to distribute or communicate copies of the Original Work and Derivative
  Works to the public, with the proviso that copies of Original Work or
  Derivative Works that You distribute or communicate shall be licensed under
  this Open Software License;

  d) to perform the Original Work publicly; and

  e) to display the Original Work publicly.

2) Grant of Patent License. Licensor grants You a worldwide, royalty-free,
non-exclusive, sublicensable license, under patent claims owned or controlled
by the Licensor that are embodied in the Original Work as furnished by the
Licensor, for the duration of the patents, to make, use, sell, offer for sale,
have made, and import the Original Work and Derivative Works.

3) Grant of Source Code License. The term "Source Code" means the preferred
form of the Original Work for making modifications to it and all available
documentation describing how to modify the Original Work. Licensor agrees to
provide a machine-readable copy of the Source Code of the Original Work along
with each copy of the Original Work that Licensor distributes. Licensor
reserves the right to satisfy this obligation by placing a machine-readable
copy of the Source Code in an information repository reasonably calculated to
permit inexpensive and convenient access by You for as long as Licensor
continues to distribute the Original Work.

4) Exclusions From License Grant. Neither the names of Licensor, nor the names
of any contributors to the Original Work, nor any of their trademarks or
service marks, may be used to endorse or promote products derived from this
Original Work without express prior permission of the Licensor. Except as
expressly stated herein, nothing in this License grants any license to
Licensor's trademarks, copyrights, patents, trade secrets or any other
intellectual property. No patent license is granted to make, use, sell, offer
for sale, have made, or import embodiments of any patent claims other than the
licensed claims defined in Section 2. No license is granted to the trademarks
of Licensor even if such marks are included in the Original Work. Nothing in
this License shall be interpreted to prohibit Licensor from licensing under
terms different from this License any Original Work that Licensor otherwise
would have a right to license.

5) External Deployment. The term "External Deployment" means the use,
distribution, or communication of the Original Work or Derivative Works in any
way such that the Original Work or Derivative Works may be used by anyone
other than You, whether those works are distributed or communicated to those
persons or made available as an application intended for use over a network.
As an express condition for the grants of license hereunder, You must treat
any External Deployment by You of the Original Work or a Derivative Work as a
distribution under section 1(c).

6) Attribution Rights. You must retain, in the Source Code of any Derivative
Works that You create, all copyright, patent, or trademark notices from the
Source Code of the Original Work, as well as any notices of licensing and any
descriptive text identified therein as an "Attribution Notice." You must cause
the Source Code for any Derivative Works that You create to carry a prominent
Attribution Notice reasonably calculated to inform recipients that You have
modified the Original Work.

7) Warranty of Provenance and Disclaimer of Warranty. Licensor warrants that
the copyright in and to the Original Work and the patent rights granted herein
by Licensor are owned by the Licensor or are sublicensed to You under the
terms of this License with the permission of the contributor(s) of those
copyrights and patent rights. Except as expressly stated in the immediately
preceding sentence, the Original Work is provided under this License on an "AS
IS" BASIS and WITHOUT WARRANTY, either express or implied, including, without
limitation, the warranties of non-infringement, merchantability or fitness for
a particular purpose. THE ENTIRE RISK AS TO THE QUALITY OF THE ORIGINAL WORK
IS WITH YOU. This DISCLAIMER OF WARRANTY constitutes an essential part of this
License. No license to the Original Work is granted by this License except
under this disclaimer.

8) Limitation of Liability. Under no circumstances and under no legal theory,
whether in tort (including negligence), contract, or otherwise, shall the
Licensor be liable to anyone for any indirect, special, incidental, or
consequential damages of any character arising as a result of this License or
the use of the Original Work including, without limitation, damages for loss
of goodwill, work stoppage, computer failure or malfunction, or any and all
other commercial damages or losses. This limitation of liability shall not
apply to the extent applicable law prohibits such limitation.

9) Acceptance and Termination. If, at any time, You expressly assented to this
License, that assent indicates your clear and irrevocable acceptance of this
License and all of its terms and conditions. If You distribute or communicate
copies of the Original Work or a Derivative Work, You must make a reasonable
effort under the circumstances to obtain the express assent of recipients to
the terms of this License. This License conditions your rights to undertake
the activities listed in Section 1, including your right to create Derivative
Works based upon the Original Work, and doing so without honoring these terms
and conditions is prohibited by copyright law and international treaty.
Nothing in this License is intended to affect copyright exceptions and
limitations (including "fair use" or "fair dealing"). This License shall
terminate immediately and You may no longer exercise any of the rights granted
to You by this License upon your failure to honor the conditions in Section
1(c).

10) Termination for Patent Action. This License shall terminate automatically
and You may no longer exercise any of the rights granted to You by this
License as of the date You commence an action, including a cross-claim or
counterclaim, against Licensor or any licensee alleging that the Original Work
infringes a patent. This termination provision shall not apply for an action
alleging patent infringement by combinations of the Original Work with other
software or hardware.

11) Jurisdiction, Venue and Governing Law. Any action or suit relating to this
License may be brought only in the courts of a jurisdiction wherein the
Licensor resides or in which Licensor conducts its primary business, and under
the laws of that jurisdiction excluding its conflict-of-law provisions. The
application of the United Nations Convention on Contracts for the
International Sale of Goods is expressly excluded. Any use of the Original
Work outside the scope of this License or after its termination shall be
subject to the requirements and penalties of copyright or patent law in the
appropriate jurisdiction. This section shall survive the termination of this
License.

12) Attorneys' Fees. In any action to enforce the terms of this License or
seeking damages relating thereto, the prevailing party shall be entitled to
recover its costs and expenses, including, without limitation, reasonable
attorneys' fees and costs incurred in connection with such action, including
any appeal of such action. This section shall survive the termination of this
License.

13) Miscellaneous. If any provision of this License is held to be
unenforceable, such provision shall be reformed only to the extent necessary
to make it enforceable.

14) Definition of "You" in This License. "You" throughout this License,
whether in upper or lower case, means an individual or a legal entity
exercising rights under, and complying with all of the terms of, this License.
For legal entities, "You" includes any entity that controls, is controlled by,
or is under common control with you. For purposes of this definition,
"control" means (i) the power, direct or indirect, to cause the direction or
management of such entity, whether by contract or otherwise, or (ii) ownership
of fifty percent (50%) or more of the outstanding shares, or (iii) beneficial
ownership of such entity.

15) Right to Use. You may use the Original Work in all ways not otherwise
restricted or conditioned by this License or by law, and Licensor promises not
to interfere with or be responsible for such uses by You.

16) Modification of This License. This License is Copyright © 2005 Lawrence
Rosen. Permission is granted to copy, distribute, or communicate this License
without modification. Nothing in this License permits You to modify this
License as applied to the Original Work or to Derivative Works. However, You
may modify the text of this License and copy, distribute or communicate your
modified version (the "Modified License") and apply it to other original works
of authorship subject to the following conditions: (i) You may not indicate in
any way that your Modified License is the "Open Software License" or "OSL" and
you may not use those names in the name of your Modified License; (ii) You
must replace the notice specified in the first paragraph above with the notice
"Licensed under <insert your license name here>" or with a notice of your own
that is not confusingly similar to the notice in this License; and (iii) You
may not claim that your original works are open source software unless your
Modified License has been approved by Open Source Initiative (OSI) and You
comply with its license review and certification process.

"""

let licenseLGPL3Contents = """
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

let licenseLGPL3LinkingExceptionContents = """
This software is licensed under the LGPL3, included below.

As a special exception to the GNU Lesser General Public License version 3
("LGPL3"), the copyright holders of this Library give you permission to
convey to a third party a Combined Work that links statically or dynamically
to this Library without providing any Minimal Corresponding Source or
Minimal Application Code as set out in 4d or providing the installation
information set out in section 4e, provided that you comply with the other
provisions of LGPL3 and provided that you meet, for the Application the
terms and conditions of the license(s) which apply to the Application.

Except as stated in this special exception, the provisions of LGPL3 will
continue to comply in full to this Library. If you modify this Library, you
may apply this exception to your version of this Library, but you are not
obliged to do so. If you do not wish to do so, delete this exception
statement from your version. This exception does not (and cannot) modify any
license terms which apply to the Application, with which you must still
comply.


"""

let licenseGPL2Contents = """
                    GNU GENERAL PUBLIC LICENSE
                       Version 2, June 1991

 Copyright (C) 1989, 1991 Free Software Foundation, Inc.,
 <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The licenses for most software are designed to take away your
freedom to share and change it.  By contrast, the GNU General Public
License is intended to guarantee your freedom to share and change free
software--to make sure the software is free for all its users.  This
General Public License applies to most of the Free Software
Foundation's software and to any other program whose authors commit to
using it.  (Some other Free Software Foundation software is covered by
the GNU Lesser General Public License instead.)  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
this service if you wish), that you receive source code or can get it
if you want it, that you can change the software or use pieces of it
in new free programs; and that you know you can do these things.

  To protect your rights, we need to make restrictions that forbid
anyone to deny you these rights or to ask you to surrender the rights.
These restrictions translate to certain responsibilities for you if you
distribute copies of the software, or if you modify it.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must give the recipients all the rights that
you have.  You must make sure that they, too, receive or can get the
source code.  And you must show them these terms so they know their
rights.

  We protect your rights with two steps: (1) copyright the software, and
(2) offer you this license which gives you legal permission to copy,
distribute and/or modify the software.

  Also, for each author's protection and ours, we want to make certain
that everyone understands that there is no warranty for this free
software.  If the software is modified by someone else and passed on, we
want its recipients to know that what they have is not the original, so
that any problems introduced by others will not reflect on the original
authors' reputations.

  Finally, any free program is threatened constantly by software
patents.  We wish to avoid the danger that redistributors of a free
program will individually obtain patent licenses, in effect making the
program proprietary.  To prevent this, we have made it clear that any
patent must be licensed for everyone's free use or not licensed at all.

  The precise terms and conditions for copying, distribution and
modification follow.

                    GNU GENERAL PUBLIC LICENSE
   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

  0. This License applies to any program or other work which contains
a notice placed by the copyright holder saying it may be distributed
under the terms of this General Public License.  The "Program", below,
refers to any such program or work, and a "work based on the Program"
means either the Program or any derivative work under copyright law:
that is to say, a work containing the Program or a portion of it,
either verbatim or with modifications and/or translated into another
language.  (Hereinafter, translation is included without limitation in
the term "modification".)  Each licensee is addressed as "you".

Activities other than copying, distribution and modification are not
covered by this License; they are outside its scope.  The act of
running the Program is not restricted, and the output from the Program
is covered only if its contents constitute a work based on the
Program (independent of having been made by running the Program).
Whether that is true depends on what the Program does.

  1. You may copy and distribute verbatim copies of the Program's
source code as you receive it, in any medium, provided that you
conspicuously and appropriately publish on each copy an appropriate
copyright notice and disclaimer of warranty; keep intact all the
notices that refer to this License and to the absence of any warranty;
and give any other recipients of the Program a copy of this License
along with the Program.

You may charge a fee for the physical act of transferring a copy, and
you may at your option offer warranty protection in exchange for a fee.

  2. You may modify your copy or copies of the Program or any portion
of it, thus forming a work based on the Program, and copy and
distribute such modifications or work under the terms of Section 1
above, provided that you also meet all of these conditions:

    a) You must cause the modified files to carry prominent notices
    stating that you changed the files and the date of any change.

    b) You must cause any work that you distribute or publish, that in
    whole or in part contains or is derived from the Program or any
    part thereof, to be licensed as a whole at no charge to all third
    parties under the terms of this License.

    c) If the modified program normally reads commands interactively
    when run, you must cause it, when started running for such
    interactive use in the most ordinary way, to print or display an
    announcement including an appropriate copyright notice and a
    notice that there is no warranty (or else, saying that you provide
    a warranty) and that users may redistribute the program under
    these conditions, and telling the user how to view a copy of this
    License.  (Exception: if the Program itself is interactive but
    does not normally print such an announcement, your work based on
    the Program is not required to print an announcement.)

These requirements apply to the modified work as a whole.  If
identifiable sections of that work are not derived from the Program,
and can be reasonably considered independent and separate works in
themselves, then this License, and its terms, do not apply to those
sections when you distribute them as separate works.  But when you
distribute the same sections as part of a whole which is a work based
on the Program, the distribution of the whole must be on the terms of
this License, whose permissions for other licensees extend to the
entire whole, and thus to each and every part regardless of who wrote it.

Thus, it is not the intent of this section to claim rights or contest
your rights to work written entirely by you; rather, the intent is to
exercise the right to control the distribution of derivative or
collective works based on the Program.

In addition, mere aggregation of another work not based on the Program
with the Program (or with a work based on the Program) on a volume of
a storage or distribution medium does not bring the other work under
the scope of this License.

  3. You may copy and distribute the Program (or a work based on it,
under Section 2) in object code or executable form under the terms of
Sections 1 and 2 above provided that you also do one of the following:

    a) Accompany it with the complete corresponding machine-readable
    source code, which must be distributed under the terms of Sections
    1 and 2 above on a medium customarily used for software interchange; or,

    b) Accompany it with a written offer, valid for at least three
    years, to give any third party, for a charge no more than your
    cost of physically performing source distribution, a complete
    machine-readable copy of the corresponding source code, to be
    distributed under the terms of Sections 1 and 2 above on a medium
    customarily used for software interchange; or,

    c) Accompany it with the information you received as to the offer
    to distribute corresponding source code.  (This alternative is
    allowed only for noncommercial distribution and only if you
    received the program in object code or executable form with such
    an offer, in accord with Subsection b above.)

The source code for a work means the preferred form of the work for
making modifications to it.  For an executable work, complete source
code means all the source code for all modules it contains, plus any
associated interface definition files, plus the scripts used to
control compilation and installation of the executable.  However, as a
special exception, the source code distributed need not include
anything that is normally distributed (in either source or binary
form) with the major components (compiler, kernel, and so on) of the
operating system on which the executable runs, unless that component
itself accompanies the executable.

If distribution of executable or object code is made by offering
access to copy from a designated place, then offering equivalent
access to copy the source code from the same place counts as
distribution of the source code, even though third parties are not
compelled to copy the source along with the object code.

  4. You may not copy, modify, sublicense, or distribute the Program
except as expressly provided under this License.  Any attempt
otherwise to copy, modify, sublicense or distribute the Program is
void, and will automatically terminate your rights under this License.
However, parties who have received copies, or rights, from you under
this License will not have their licenses terminated so long as such
parties remain in full compliance.

  5. You are not required to accept this License, since you have not
signed it.  However, nothing else grants you permission to modify or
distribute the Program or its derivative works.  These actions are
prohibited by law if you do not accept this License.  Therefore, by
modifying or distributing the Program (or any work based on the
Program), you indicate your acceptance of this License to do so, and
all its terms and conditions for copying, distributing or modifying
the Program or works based on it.

  6. Each time you redistribute the Program (or any work based on the
Program), the recipient automatically receives a license from the
original licensor to copy, distribute or modify the Program subject to
these terms and conditions.  You may not impose any further
restrictions on the recipients' exercise of the rights granted herein.
You are not responsible for enforcing compliance by third parties to
this License.

  7. If, as a consequence of a court judgment or allegation of patent
infringement or for any other reason (not limited to patent issues),
conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot
distribute so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you
may not distribute the Program at all.  For example, if a patent
license would not permit royalty-free redistribution of the Program by
all those who receive copies directly or indirectly through you, then
the only way you could satisfy both it and this License would be to
refrain entirely from distribution of the Program.

If any portion of this section is held invalid or unenforceable under
any particular circumstance, the balance of the section is intended to
apply and the section as a whole is intended to apply in other
circumstances.

It is not the purpose of this section to induce you to infringe any
patents or other property right claims or to contest validity of any
such claims; this section has the sole purpose of protecting the
integrity of the free software distribution system, which is
implemented by public license practices.  Many people have made
generous contributions to the wide range of software distributed
through that system in reliance on consistent application of that
system; it is up to the author/donor to decide if he or she is willing
to distribute software through any other system and a licensee cannot
impose that choice.

This section is intended to make thoroughly clear what is believed to
be a consequence of the rest of this License.

  8. If the distribution and/or use of the Program is restricted in
certain countries either by patents or by copyrighted interfaces, the
original copyright holder who places the Program under this License
may add an explicit geographical distribution limitation excluding
those countries, so that distribution is permitted only in or among
countries not thus excluded.  In such case, this License incorporates
the limitation as if written in the body of this License.

  9. The Free Software Foundation may publish revised and/or new versions
of the General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

Each version is given a distinguishing version number.  If the Program
specifies a version number of this License which applies to it and "any
later version", you have the option of following the terms and conditions
either of that version or of any later version published by the Free
Software Foundation.  If the Program does not specify a version number of
this License, you may choose any version ever published by the Free Software
Foundation.

  10. If you wish to incorporate parts of the Program into other free
programs whose distribution conditions are different, write to the author
to ask for permission.  For software which is copyrighted by the Free
Software Foundation, write to the Free Software Foundation; we sometimes
make exceptions for this.  Our decision will be guided by the two goals
of preserving the free status of all derivatives of our free software and
of promoting the sharing and reuse of software generally.

                            NO WARRANTY

  11. BECAUSE THE PROGRAM IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW.  EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED
OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  THE ENTIRE RISK AS
TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU.  SHOULD THE
PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING,
REPAIR OR CORRECTION.

  12. IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES,
INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING
OUT OF THE USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED
TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY
YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER
PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
convey the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

If the program is interactive, make it output a short notice like this
when it starts in an interactive mode:

    Gnomovision version 69, Copyright (C) year name of author
    Gnomovision comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, the commands you use may
be called something other than `show w' and `show c'; they could even be
mouse-clicks or menu items--whatever suits your program.

You should also get your employer (if you work as a programmer) or your
school, if any, to sign a "copyright disclaimer" for the program, if
necessary.  Here is a sample; alter the names:

  Yoyodyne, Inc., hereby disclaims all copyright interest in the program
  `Gnomovision' (which makes passes at compilers) written by James Hacker.

  <signature of Moe Ghoul>, 1 April 1989
  Moe Ghoul, President of Vice

This General Public License does not permit incorporating your program into
proprietary programs.  If your program is a subroutine library, you may
consider it more useful to permit linking proprietary applications with the
library.  If this is what you want to do, use the GNU Lesser General
Public License instead of this License.

"""


let licenseGPL3Contents = """
                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007

 Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
 Everyone is permitted to copy and distribute verbatim copies
 of this license document, but changing it is not allowed.

                            Preamble

  The GNU General Public License is a free, copyleft license for
software and other kinds of works.

  The licenses for most software and other practical works are designed
to take away your freedom to share and change the works.  By contrast,
the GNU General Public License is intended to guarantee your freedom to
share and change all versions of a program--to make sure it remains free
software for all its users.  We, the Free Software Foundation, use the
GNU General Public License for most of our software; it applies also to
any other work released this way by its authors.  You can apply it to
your programs, too.

  When we speak of free software, we are referring to freedom, not
price.  Our General Public Licenses are designed to make sure that you
have the freedom to distribute copies of free software (and charge for
them if you wish), that you receive source code or can get it if you
want it, that you can change the software or use pieces of it in new
free programs, and that you know you can do these things.

  To protect your rights, we need to prevent others from denying you
these rights or asking you to surrender the rights.  Therefore, you have
certain responsibilities if you distribute copies of the software, or if
you modify it: responsibilities to respect the freedom of others.

  For example, if you distribute copies of such a program, whether
gratis or for a fee, you must pass on to the recipients the same
freedoms that you received.  You must make sure that they, too, receive
or can get the source code.  And you must show them these terms so they
know their rights.

  Developers that use the GNU GPL protect your rights with two steps:
(1) assert copyright on the software, and (2) offer you this License
giving you legal permission to copy, distribute and/or modify it.

  For the developers' and authors' protection, the GPL clearly explains
that there is no warranty for this free software.  For both users' and
authors' sake, the GPL requires that modified versions be marked as
changed, so that their problems will not be attributed erroneously to
authors of previous versions.

  Some devices are designed to deny users access to install or run
modified versions of the software inside them, although the manufacturer
can do so.  This is fundamentally incompatible with the aim of
protecting users' freedom to change the software.  The systematic
pattern of such abuse occurs in the area of products for individuals to
use, which is precisely where it is most unacceptable.  Therefore, we
have designed this version of the GPL to prohibit the practice for those
products.  If such problems arise substantially in other domains, we
stand ready to extend this provision to those domains in future versions
of the GPL, as needed to protect the freedom of users.

  Finally, every program is threatened constantly by software patents.
States should not allow patents to restrict development and use of
software on general-purpose computers, but in those that do, we wish to
avoid the special danger that patents applied to a free program could
make it effectively proprietary.  To prevent this, the GPL assures that
patents cannot be used to render the program non-free.

  The precise terms and conditions for copying, distribution and
modification follow.

                       TERMS AND CONDITIONS

  0. Definitions.

  "This License" refers to version 3 of the GNU General Public License.

  "Copyright" also means copyright-like laws that apply to other kinds of
works, such as semiconductor masks.

  "The Program" refers to any copyrightable work licensed under this
License.  Each licensee is addressed as "you".  "Licensees" and
"recipients" may be individuals or organizations.

  To "modify" a work means to copy from or adapt all or part of the work
in a fashion requiring copyright permission, other than the making of an
exact copy.  The resulting work is called a "modified version" of the
earlier work or a work "based on" the earlier work.

  A "covered work" means either the unmodified Program or a work based
on the Program.

  To "propagate" a work means to do anything with it that, without
permission, would make you directly or secondarily liable for
infringement under applicable copyright law, except executing it on a
computer or modifying a private copy.  Propagation includes copying,
distribution (with or without modification), making available to the
public, and in some countries other activities as well.

  To "convey" a work means any kind of propagation that enables other
parties to make or receive copies.  Mere interaction with a user through
a computer network, with no transfer of a copy, is not conveying.

  An interactive user interface displays "Appropriate Legal Notices"
to the extent that it includes a convenient and prominently visible
feature that (1) displays an appropriate copyright notice, and (2)
tells the user that there is no warranty for the work (except to the
extent that warranties are provided), that licensees may convey the
work under this License, and how to view a copy of this License.  If
the interface presents a list of user commands or options, such as a
menu, a prominent item in the list meets this criterion.

  1. Source Code.

  The "source code" for a work means the preferred form of the work
for making modifications to it.  "Object code" means any non-source
form of a work.

  A "Standard Interface" means an interface that either is an official
standard defined by a recognized standards body, or, in the case of
interfaces specified for a particular programming language, one that
is widely used among developers working in that language.

  The "System Libraries" of an executable work include anything, other
than the work as a whole, that (a) is included in the normal form of
packaging a Major Component, but which is not part of that Major
Component, and (b) serves only to enable use of the work with that
Major Component, or to implement a Standard Interface for which an
implementation is available to the public in source code form.  A
"Major Component", in this context, means a major essential component
(kernel, window system, and so on) of the specific operating system
(if any) on which the executable work runs, or a compiler used to
produce the work, or an object code interpreter used to run it.

  The "Corresponding Source" for a work in object code form means all
the source code needed to generate, install, and (for an executable
work) run the object code and to modify the work, including scripts to
control those activities.  However, it does not include the work's
System Libraries, or general-purpose tools or generally available free
programs which are used unmodified in performing those activities but
which are not part of the work.  For example, Corresponding Source
includes interface definition files associated with source files for
the work, and the source code for shared libraries and dynamically
linked subprograms that the work is specifically designed to require,
such as by intimate data communication or control flow between those
subprograms and other parts of the work.

  The Corresponding Source need not include anything that users
can regenerate automatically from other parts of the Corresponding
Source.

  The Corresponding Source for a work in source code form is that
same work.

  2. Basic Permissions.

  All rights granted under this License are granted for the term of
copyright on the Program, and are irrevocable provided the stated
conditions are met.  This License explicitly affirms your unlimited
permission to run the unmodified Program.  The output from running a
covered work is covered by this License only if the output, given its
content, constitutes a covered work.  This License acknowledges your
rights of fair use or other equivalent, as provided by copyright law.

  You may make, run and propagate covered works that you do not
convey, without conditions so long as your license otherwise remains
in force.  You may convey covered works to others for the sole purpose
of having them make modifications exclusively for you, or provide you
with facilities for running those works, provided that you comply with
the terms of this License in conveying all material for which you do
not control copyright.  Those thus making or running the covered works
for you must do so exclusively on your behalf, under your direction
and control, on terms that prohibit them from making any copies of
your copyrighted material outside their relationship with you.

  Conveying under any other circumstances is permitted solely under
the conditions stated below.  Sublicensing is not allowed; section 10
makes it unnecessary.

  3. Protecting Users' Legal Rights From Anti-Circumvention Law.

  No covered work shall be deemed part of an effective technological
measure under any applicable law fulfilling obligations under article
11 of the WIPO copyright treaty adopted on 20 December 1996, or
similar laws prohibiting or restricting circumvention of such
measures.

  When you convey a covered work, you waive any legal power to forbid
circumvention of technological measures to the extent such circumvention
is effected by exercising rights under this License with respect to
the covered work, and you disclaim any intention to limit operation or
modification of the work as a means of enforcing, against the work's
users, your or third parties' legal rights to forbid circumvention of
technological measures.

  4. Conveying Verbatim Copies.

  You may convey verbatim copies of the Program's source code as you
receive it, in any medium, provided that you conspicuously and
appropriately publish on each copy an appropriate copyright notice;
keep intact all notices stating that this License and any
non-permissive terms added in accord with section 7 apply to the code;
keep intact all notices of the absence of any warranty; and give all
recipients a copy of this License along with the Program.

  You may charge any price or no price for each copy that you convey,
and you may offer support or warranty protection for a fee.

  5. Conveying Modified Source Versions.

  You may convey a work based on the Program, or the modifications to
produce it from the Program, in the form of source code under the
terms of section 4, provided that you also meet all of these conditions:

    a) The work must carry prominent notices stating that you modified
    it, and giving a relevant date.

    b) The work must carry prominent notices stating that it is
    released under this License and any conditions added under section
    7.  This requirement modifies the requirement in section 4 to
    "keep intact all notices".

    c) You must license the entire work, as a whole, under this
    License to anyone who comes into possession of a copy.  This
    License will therefore apply, along with any applicable section 7
    additional terms, to the whole of the work, and all its parts,
    regardless of how they are packaged.  This License gives no
    permission to license the work in any other way, but it does not
    invalidate such permission if you have separately received it.

    d) If the work has interactive user interfaces, each must display
    Appropriate Legal Notices; however, if the Program has interactive
    interfaces that do not display Appropriate Legal Notices, your
    work need not make them do so.

  A compilation of a covered work with other separate and independent
works, which are not by their nature extensions of the covered work,
and which are not combined with it such as to form a larger program,
in or on a volume of a storage or distribution medium, is called an
"aggregate" if the compilation and its resulting copyright are not
used to limit the access or legal rights of the compilation's users
beyond what the individual works permit.  Inclusion of a covered work
in an aggregate does not cause this License to apply to the other
parts of the aggregate.

  6. Conveying Non-Source Forms.

  You may convey a covered work in object code form under the terms
of sections 4 and 5, provided that you also convey the
machine-readable Corresponding Source under the terms of this License,
in one of these ways:

    a) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by the
    Corresponding Source fixed on a durable physical medium
    customarily used for software interchange.

    b) Convey the object code in, or embodied in, a physical product
    (including a physical distribution medium), accompanied by a
    written offer, valid for at least three years and valid for as
    long as you offer spare parts or customer support for that product
    model, to give anyone who possesses the object code either (1) a
    copy of the Corresponding Source for all the software in the
    product that is covered by this License, on a durable physical
    medium customarily used for software interchange, for a price no
    more than your reasonable cost of physically performing this
    conveying of source, or (2) access to copy the
    Corresponding Source from a network server at no charge.

    c) Convey individual copies of the object code with a copy of the
    written offer to provide the Corresponding Source.  This
    alternative is allowed only occasionally and noncommercially, and
    only if you received the object code with such an offer, in accord
    with subsection 6b.

    d) Convey the object code by offering access from a designated
    place (gratis or for a charge), and offer equivalent access to the
    Corresponding Source in the same way through the same place at no
    further charge.  You need not require recipients to copy the
    Corresponding Source along with the object code.  If the place to
    copy the object code is a network server, the Corresponding Source
    may be on a different server (operated by you or a third party)
    that supports equivalent copying facilities, provided you maintain
    clear directions next to the object code saying where to find the
    Corresponding Source.  Regardless of what server hosts the
    Corresponding Source, you remain obligated to ensure that it is
    available for as long as needed to satisfy these requirements.

    e) Convey the object code using peer-to-peer transmission, provided
    you inform other peers where the object code and Corresponding
    Source of the work are being offered to the general public at no
    charge under subsection 6d.

  A separable portion of the object code, whose source code is excluded
from the Corresponding Source as a System Library, need not be
included in conveying the object code work.

  A "User Product" is either (1) a "consumer product", which means any
tangible personal property which is normally used for personal, family,
or household purposes, or (2) anything designed or sold for incorporation
into a dwelling.  In determining whether a product is a consumer product,
doubtful cases shall be resolved in favor of coverage.  For a particular
product received by a particular user, "normally used" refers to a
typical or common use of that class of product, regardless of the status
of the particular user or of the way in which the particular user
actually uses, or expects or is expected to use, the product.  A product
is a consumer product regardless of whether the product has substantial
commercial, industrial or non-consumer uses, unless such uses represent
the only significant mode of use of the product.

  "Installation Information" for a User Product means any methods,
procedures, authorization keys, or other information required to install
and execute modified versions of a covered work in that User Product from
a modified version of its Corresponding Source.  The information must
suffice to ensure that the continued functioning of the modified object
code is in no case prevented or interfered with solely because
modification has been made.

  If you convey an object code work under this section in, or with, or
specifically for use in, a User Product, and the conveying occurs as
part of a transaction in which the right of possession and use of the
User Product is transferred to the recipient in perpetuity or for a
fixed term (regardless of how the transaction is characterized), the
Corresponding Source conveyed under this section must be accompanied
by the Installation Information.  But this requirement does not apply
if neither you nor any third party retains the ability to install
modified object code on the User Product (for example, the work has
been installed in ROM).

  The requirement to provide Installation Information does not include a
requirement to continue to provide support service, warranty, or updates
for a work that has been modified or installed by the recipient, or for
the User Product in which it has been modified or installed.  Access to a
network may be denied when the modification itself materially and
adversely affects the operation of the network or violates the rules and
protocols for communication across the network.

  Corresponding Source conveyed, and Installation Information provided,
in accord with this section must be in a format that is publicly
documented (and with an implementation available to the public in
source code form), and must require no special password or key for
unpacking, reading or copying.

  7. Additional Terms.

  "Additional permissions" are terms that supplement the terms of this
License by making exceptions from one or more of its conditions.
Additional permissions that are applicable to the entire Program shall
be treated as though they were included in this License, to the extent
that they are valid under applicable law.  If additional permissions
apply only to part of the Program, that part may be used separately
under those permissions, but the entire Program remains governed by
this License without regard to the additional permissions.

  When you convey a copy of a covered work, you may at your option
remove any additional permissions from that copy, or from any part of
it.  (Additional permissions may be written to require their own
removal in certain cases when you modify the work.)  You may place
additional permissions on material, added by you to a covered work,
for which you have or can give appropriate copyright permission.

  Notwithstanding any other provision of this License, for material you
add to a covered work, you may (if authorized by the copyright holders of
that material) supplement the terms of this License with terms:

    a) Disclaiming warranty or limiting liability differently from the
    terms of sections 15 and 16 of this License; or

    b) Requiring preservation of specified reasonable legal notices or
    author attributions in that material or in the Appropriate Legal
    Notices displayed by works containing it; or

    c) Prohibiting misrepresentation of the origin of that material, or
    requiring that modified versions of such material be marked in
    reasonable ways as different from the original version; or

    d) Limiting the use for publicity purposes of names of licensors or
    authors of the material; or

    e) Declining to grant rights under trademark law for use of some
    trade names, trademarks, or service marks; or

    f) Requiring indemnification of licensors and authors of that
    material by anyone who conveys the material (or modified versions of
    it) with contractual assumptions of liability to the recipient, for
    any liability that these contractual assumptions directly impose on
    those licensors and authors.

  All other non-permissive additional terms are considered "further
restrictions" within the meaning of section 10.  If the Program as you
received it, or any part of it, contains a notice stating that it is
governed by this License along with a term that is a further
restriction, you may remove that term.  If a license document contains
a further restriction but permits relicensing or conveying under this
License, you may add to a covered work material governed by the terms
of that license document, provided that the further restriction does
not survive such relicensing or conveying.

  If you add terms to a covered work in accord with this section, you
must place, in the relevant source files, a statement of the
additional terms that apply to those files, or a notice indicating
where to find the applicable terms.

  Additional terms, permissive or non-permissive, may be stated in the
form of a separately written license, or stated as exceptions;
the above requirements apply either way.

  8. Termination.

  You may not propagate or modify a covered work except as expressly
provided under this License.  Any attempt otherwise to propagate or
modify it is void, and will automatically terminate your rights under
this License (including any patent licenses granted under the third
paragraph of section 11).

  However, if you cease all violation of this License, then your
license from a particular copyright holder is reinstated (a)
provisionally, unless and until the copyright holder explicitly and
finally terminates your license, and (b) permanently, if the copyright
holder fails to notify you of the violation by some reasonable means
prior to 60 days after the cessation.

  Moreover, your license from a particular copyright holder is
reinstated permanently if the copyright holder notifies you of the
violation by some reasonable means, this is the first time you have
received notice of violation of this License (for any work) from that
copyright holder, and you cure the violation prior to 30 days after
your receipt of the notice.

  Termination of your rights under this section does not terminate the
licenses of parties who have received copies or rights from you under
this License.  If your rights have been terminated and not permanently
reinstated, you do not qualify to receive new licenses for the same
material under section 10.

  9. Acceptance Not Required for Having Copies.

  You are not required to accept this License in order to receive or
run a copy of the Program.  Ancillary propagation of a covered work
occurring solely as a consequence of using peer-to-peer transmission
to receive a copy likewise does not require acceptance.  However,
nothing other than this License grants you permission to propagate or
modify any covered work.  These actions infringe copyright if you do
not accept this License.  Therefore, by modifying or propagating a
covered work, you indicate your acceptance of this License to do so.

  10. Automatic Licensing of Downstream Recipients.

  Each time you convey a covered work, the recipient automatically
receives a license from the original licensors, to run, modify and
propagate that work, subject to this License.  You are not responsible
for enforcing compliance by third parties with this License.

  An "entity transaction" is a transaction transferring control of an
organization, or substantially all assets of one, or subdividing an
organization, or merging organizations.  If propagation of a covered
work results from an entity transaction, each party to that
transaction who receives a copy of the work also receives whatever
licenses to the work the party's predecessor in interest had or could
give under the previous paragraph, plus a right to possession of the
Corresponding Source of the work from the predecessor in interest, if
the predecessor has it or can get it with reasonable efforts.

  You may not impose any further restrictions on the exercise of the
rights granted or affirmed under this License.  For example, you may
not impose a license fee, royalty, or other charge for exercise of
rights granted under this License, and you may not initiate litigation
(including a cross-claim or counterclaim in a lawsuit) alleging that
any patent claim is infringed by making, using, selling, offering for
sale, or importing the Program or any portion of it.

  11. Patents.

  A "contributor" is a copyright holder who authorizes use under this
License of the Program or a work on which the Program is based.  The
work thus licensed is called the contributor's "contributor version".

  A contributor's "essential patent claims" are all patent claims
owned or controlled by the contributor, whether already acquired or
hereafter acquired, that would be infringed by some manner, permitted
by this License, of making, using, or selling its contributor version,
but do not include claims that would be infringed only as a
consequence of further modification of the contributor version.  For
purposes of this definition, "control" includes the right to grant
patent sublicenses in a manner consistent with the requirements of
this License.

  Each contributor grants you a non-exclusive, worldwide, royalty-free
patent license under the contributor's essential patent claims, to
make, use, sell, offer for sale, import and otherwise run, modify and
propagate the contents of its contributor version.

  In the following three paragraphs, a "patent license" is any express
agreement or commitment, however denominated, not to enforce a patent
(such as an express permission to practice a patent or covenant not to
sue for patent infringement).  To "grant" such a patent license to a
party means to make such an agreement or commitment not to enforce a
patent against the party.

  If you convey a covered work, knowingly relying on a patent license,
and the Corresponding Source of the work is not available for anyone
to copy, free of charge and under the terms of this License, through a
publicly available network server or other readily accessible means,
then you must either (1) cause the Corresponding Source to be so
available, or (2) arrange to deprive yourself of the benefit of the
patent license for this particular work, or (3) arrange, in a manner
consistent with the requirements of this License, to extend the patent
license to downstream recipients.  "Knowingly relying" means you have
actual knowledge that, but for the patent license, your conveying the
covered work in a country, or your recipient's use of the covered work
in a country, would infringe one or more identifiable patents in that
country that you have reason to believe are valid.

  If, pursuant to or in connection with a single transaction or
arrangement, you convey, or propagate by procuring conveyance of, a
covered work, and grant a patent license to some of the parties
receiving the covered work authorizing them to use, propagate, modify
or convey a specific copy of the covered work, then the patent license
you grant is automatically extended to all recipients of the covered
work and works based on it.

  A patent license is "discriminatory" if it does not include within
the scope of its coverage, prohibits the exercise of, or is
conditioned on the non-exercise of one or more of the rights that are
specifically granted under this License.  You may not convey a covered
work if you are a party to an arrangement with a third party that is
in the business of distributing software, under which you make payment
to the third party based on the extent of your activity of conveying
the work, and under which the third party grants, to any of the
parties who would receive the covered work from you, a discriminatory
patent license (a) in connection with copies of the covered work
conveyed by you (or copies made from those copies), or (b) primarily
for and in connection with specific products or compilations that
contain the covered work, unless you entered into that arrangement,
or that patent license was granted, prior to 28 March 2007.

  Nothing in this License shall be construed as excluding or limiting
any implied license or other defenses to infringement that may
otherwise be available to you under applicable patent law.

  12. No Surrender of Others' Freedom.

  If conditions are imposed on you (whether by court order, agreement or
otherwise) that contradict the conditions of this License, they do not
excuse you from the conditions of this License.  If you cannot convey a
covered work so as to satisfy simultaneously your obligations under this
License and any other pertinent obligations, then as a consequence you may
not convey it at all.  For example, if you agree to terms that obligate you
to collect a royalty for further conveying from those to whom you convey
the Program, the only way you could satisfy both those terms and this
License would be to refrain entirely from conveying the Program.

  13. Use with the GNU Affero General Public License.

  Notwithstanding any other provision of this License, you have
permission to link or combine any covered work with a work licensed
under version 3 of the GNU Affero General Public License into a single
combined work, and to convey the resulting work.  The terms of this
License will continue to apply to the part which is the covered work,
but the special requirements of the GNU Affero General Public License,
section 13, concerning interaction through a network will apply to the
combination as such.

  14. Revised Versions of this License.

  The Free Software Foundation may publish revised and/or new versions of
the GNU General Public License from time to time.  Such new versions will
be similar in spirit to the present version, but may differ in detail to
address new problems or concerns.

  Each version is given a distinguishing version number.  If the
Program specifies that a certain numbered version of the GNU General
Public License "or any later version" applies to it, you have the
option of following the terms and conditions either of that numbered
version or of any later version published by the Free Software
Foundation.  If the Program does not specify a version number of the
GNU General Public License, you may choose any version ever published
by the Free Software Foundation.

  If the Program specifies that a proxy can decide which future
versions of the GNU General Public License can be used, that proxy's
public statement of acceptance of a version permanently authorizes you
to choose that version for the Program.

  Later license versions may give you additional or different
permissions.  However, no additional obligations are imposed on any
author or copyright holder as a result of your choosing to follow a
later version.

  15. Disclaimer of Warranty.

  THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY
APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT
HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY
OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM
IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF
ALL NECESSARY SERVICING, REPAIR OR CORRECTION.

  16. Limitation of Liability.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS
THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY
GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE
USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD
PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS),
EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.

  17. Interpretation of Sections 15 and 16.

  If the disclaimer of warranty and limitation of liability provided
above cannot be given local legal effect according to their terms,
reviewing courts shall apply local law that most closely approximates
an absolute waiver of all civil liability in connection with the
Program, unless a warranty or assumption of liability accompanies a
copy of the Program in return for a fee.

                     END OF TERMS AND CONDITIONS

            How to Apply These Terms to Your New Programs

  If you develop a new program, and you want it to be of the greatest
possible use to the public, the best way to achieve this is to make it
free software which everyone can redistribute and change under these terms.

  To do so, attach the following notices to the program.  It is safest
to attach them to the start of each source file to most effectively
state the exclusion of warranty; and each file should have at least
the "copyright" line and a pointer to where the full notice is found.

    <one line to give the program's name and a brief idea of what it does.>
    Copyright (C) <year>  <name of author>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.

Also add information on how to contact you by electronic and paper mail.

  If the program does terminal interaction, make it output a short
notice like this when it starts in an interactive mode:

    <program>  Copyright (C) <year>  <name of author>
    This program comes with ABSOLUTELY NO WARRANTY; for details type `show w'.
    This is free software, and you are welcome to redistribute it
    under certain conditions; type `show c' for details.

The hypothetical commands `show w' and `show c' should show the appropriate
parts of the General Public License.  Of course, your program's commands
might be different; for a GUI interface, you would use an "about box".

  You should also get your employer (if you work as a programmer) or school,
if any, to sign a "copyright disclaimer" for the program, if necessary.
For more information on this, and how to apply and follow the GNU GPL, see
<https://www.gnu.org/licenses/>.

  The GNU General Public License does not permit incorporating your program
into proprietary programs.  If your program is a subroutine library, you
may consider it more useful to permit linking proprietary applications with
the library.  If this is what you want to do, use the GNU Lesser General
Public License instead of this License.  But first, please read
<https://www.gnu.org/licenses/why-not-lgpl.html>.

"""

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
