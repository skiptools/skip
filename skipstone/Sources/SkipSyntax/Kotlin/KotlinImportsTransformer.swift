// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Consolidate and map import statements to Skip modules.
final class KotlinImportsTransformer: KotlinTransformer {
    func apply(to syntaxTree: KotlinSyntaxTree, translator: KotlinTranslator) -> [KotlinTransformerOutput] {
        // There's no point in running this transformer in the symbol gathering phase
        guard let codebaseInfoContext = translator.codebaseInfo else {
            return []
        }

        let exportedModuleNamesByModuleName = exportedModuleNamesByModuleName(in: codebaseInfoContext.global)

        // Translate imports and remove redundancies
        var importPaths: Set<[String]> = []
        var additionalImportDeclarations: [KotlinImportDeclaration] = []
        var lastImportDeclaration: KotlinImportDeclaration? = nil
        for importDeclaration in syntaxTree.root.statements.compactMap({ $0 as? KotlinImportDeclaration }) {
            let modulePaths = translateImport(modulePath: importDeclaration.modulePath)
            for i in 0..<modulePaths.count {
                if importPaths.insert(modulePaths[i]).inserted {
                    if i == 0 {
                        importDeclaration.modulePath = modulePaths[i]
                        lastImportDeclaration = importDeclaration
                    } else {
                        additionalImportDeclarations.append(KotlinImportDeclaration(modulePath: modulePaths[i], unmappedModulePath: importDeclaration.unmappedModulePath))
                    }
                } else if i == 0 {
                    syntaxTree.root.remove(statement: importDeclaration)
                }
            }
        }

        // Gather imports that were added to support moved extensions
        var additionalModulePaths: [[String]] = []
        syntaxTree.root.visit {
            if let classDeclaration = $0 as? KotlinClassDeclaration {
                additionalModulePaths += classDeclaration.movedExtensionImportModulePaths
            } else if let interfaceDeclaration = $0 as? KotlinInterfaceDeclaration {
                additionalModulePaths += interfaceDeclaration.movedExtensionImportModulePaths
            }
            return .recurse(nil)
        }
        for additionalModulePath in additionalModulePaths {
            let modulePaths = translateImport(modulePath: additionalModulePath)
            for modulePath in modulePaths {
                if importPaths.insert(modulePath).inserted {
                    additionalImportDeclarations.append(KotlinImportDeclaration(modulePath: modulePath, unmappedModulePath: additionalModulePath))
                }
            }
        }

        // For every imported module that re-exports other modules via `@_exported import`, also emit those imports.
        // We walk transitively so that re-exports of re-exports are followed.
        let allModulePaths = importPaths
        var queue: [[String]] = Array(allModulePaths)
        while let modulePath = queue.popLast() {
            guard modulePath.count == 1, let exportedModuleNames = exportedModuleNamesByModuleName[modulePath[0]] else {
                continue
            }
            for exportedModuleName in exportedModuleNames {
                let exportedModulePaths = translateImport(modulePath: [exportedModuleName])
                for exportedModulePath in exportedModulePaths {
                    if importPaths.insert(exportedModulePath).inserted {
                        additionalImportDeclarations.append(KotlinImportDeclaration(modulePath: exportedModulePath, unmappedModulePath: [exportedModuleName]))
                        queue.append(exportedModulePath)
                    }
                }
            }
        }

        syntaxTree.root.insert(statements: additionalImportDeclarations, after: lastImportDeclaration)
        return []
    }

    private func translateImport(modulePath: [String]) -> [[String]] {
        if modulePath.count == 1, let skipModuleNames = CodebaseInfo.moduleNameMap[modulePath[0]] {
            return skipModuleNames.map { [$0] }
        }
        return [modulePath]
    }

    /// Build a lookup from the importable module name (the post-mapping module name, e.g., `SkipSQL`) to the list of modules it re-exports.
    private func exportedModuleNamesByModuleName(in codebaseInfo: CodebaseInfo) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for dependentModule in codebaseInfo.dependentModules {
            if let moduleName = dependentModule.moduleName, let exports = dependentModule.exportedModuleNames, !exports.isEmpty {
                result[moduleName] = exports
            }
        }
        // The current module's own `@_exported import`s should also propagate when source files re-import the current module under a different name in tests.
        if let moduleName = codebaseInfo.moduleName, !codebaseInfo.exportedModuleNames.isEmpty {
            result[moduleName] = codebaseInfo.exportedModuleNames
        }
        return result
    }
}
