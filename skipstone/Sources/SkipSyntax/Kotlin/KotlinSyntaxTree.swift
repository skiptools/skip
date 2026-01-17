// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

/// Representation of the Kotlin syntax tree.
public final class KotlinSyntaxTree {
    let source: Source
    let isBridgeFile: Bool
    let autoBridge: AutoBridge
    let root: KotlinCodeBlock
    var dependencies: KotlinDependencies

    init(source: Source, isBridgeFile: Bool = false, autoBridge: AutoBridge = .default, root: KotlinCodeBlock, dependencies: KotlinDependencies = KotlinDependencies()) {
        self.source = source
        self.isBridgeFile = isBridgeFile
        self.autoBridge = autoBridge
        self.root = root
        self.dependencies = dependencies
    }

    public var messages: [Message] {
        guard !root.statements.contains(where: { $0.extras?.isSymbolFile == true }) else {
            return []
        }
        return root.subtreeMessages
    }
}
