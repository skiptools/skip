// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import Universal

/// Formatting output options for the gradle project
struct GradleOutputContext {
    /// The language to create when generating `build.gradle.kts`
    var dsl: DSL = .kotlin

    /// The supported languages for Gradle project generation
    enum DSL {
        case kotlin
        //case groovy
    }
}

struct GradleBlock : Equatable, Codable {
    var block: String?
    var param: Either<String>.Or<[String]>?
    var header: String?
    var contents: [BlockOrCommand]?
    /// Set to `false` to disable the block
    var enabled: Bool?
    /// When set to `false`, this block will not be included when inherited from another config
    var export: Bool?
    /// A set of contents to remove if they are set
    var remove: Set<String>?

    typealias BlockOrCommand = Either<String>.Or<GradleBlock>

    func filteredContents(remove: Set<String>?) -> [BlockOrCommand] {
        (contents ?? []).filter {
            switch $0 {
            case .a(let str):
                return remove?.contains(str) != true
            case .b:
                return true
            }
        }

    }
    /// Generates a `build.gradle.*` file with the specified DSL.
    public func generate(context: GradleOutputContext? = nil) -> String {
        formatted(context: context ?? GradleOutputContext(), indent: 0)
    }

    func formatted(context: GradleOutputContext, indent: Int) -> String {
        if enabled == false {
            return ""
        }
        var content = header ?? ""
        content += Self.format(blocks: contents, context: context, indent: indent)
        return content
    }

    mutating func removeContent(withExports: Bool) {
        func mapBlock(block: BlockOrCommand) -> BlockOrCommand? {
            switch block {
            case .a(let string):
                return .a(string)
            case .b(var content):
                if content.export == withExports {
                    return BlockOrCommand?.none
                } else {
                    content.removeContent(withExports: withExports)
                    return .b(content)
                }
            }
        }

        contents = contents?.compactMap(mapBlock)
    }


    private static func format(commandBlock: BlockOrCommand, context: GradleOutputContext, indent: Int) -> String {
        func formatCommand(_ command: String) -> String {
            String(repeating: " ", count: indent) + command + "\n"
        }

        func formatBlock(_ block: GradleBlock) -> String {
            var str = ""
            str += String(repeating: " ", count: indent)
            if let blockName = block.block {
                str += blockName
                if let params = block.param?.map({ [$0 ]}, { $0 }).value {
                    str += "(" + params.joined(separator: ", ") + ")"
                }
                str += " {\n"
            }
            str += block.formatted(context: context, indent: indent + 4)
            if let _ = block.block {
                str += String(repeating: " ", count: indent) + "}\n"
            }
            return str
        }

        return commandBlock.map(formatCommand, formatBlock).value
    }

    private static func format(blocks: [BlockOrCommand]?, context: GradleOutputContext, indent: Int) -> String {
        guard let blocks else { return "" }

        var content = ""
        var lastWasBlock = false
        // blocks with the same name are merged together; this allow us to use simple JSON merging
        var mergedBlocks: [(id: String?, boc: BlockOrCommand)] = []

        for boc in blocks {
            if let block = boc.infer() as GradleBlock? {
                // if a block with the same name ("block" field) exists, then update that block; otherwise, append it
                if let index = mergedBlocks.firstIndex(where: { $0.0 == block.block }) {
                    if var fromBlock = mergedBlocks[index].boc.infer() as GradleBlock? {
                        // clear any contents we have explicitly removed from a later block
                        fromBlock.contents = (fromBlock.filteredContents(remove: block.remove)) + (block.filteredContents(remove: block.remove))
                        mergedBlocks[index].boc = .init(fromBlock)
                    }
                } else {
                    mergedBlocks.append((id: block.block, boc: .init(block)))
                }
            } else {
                // command or something other than a block
                mergedBlocks.append((id: nil, boc: boc))
            }
        }
        for (index, (_, block)) in mergedBlocks.enumerated() {
            if index > 0 {
                if lastWasBlock && indent == 0 {
                    // extra space after blocks, only when at top level
                    content += "\n"
                }
            }
            content += format(commandBlock: block, context: context, indent: indent)
            lastWasBlock = (block.infer() as GradleBlock?) != nil
        }
        return content
    }

}
