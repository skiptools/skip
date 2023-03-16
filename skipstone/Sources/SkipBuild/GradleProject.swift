import Foundation
import Universal

/// A Gradle project, represented by a `build.gradle.kts` file.
///
/// https://docs.gradle.org/current/dsl/org.gradle.api.Project.html#N14DC0
public struct GradleProject : Equatable, Codable {
    private let gradle: GradleBlockContent

    private typealias BlockOrCommand = Either<String>.Or<GradleBlock>

    /// Formatting output options for the gradle project
    public struct GradleOutputContext {
        /// The language to create when generating `build.gradle.kts`
        public var dsl: DSL = .kotlin

        /// The supported languages for Gradle project generation
        public enum DSL {
            case kotlin
            //case groovy
        }
    }

    /// Generates a `build.gradle.*` file with the specified DSL.
    public func generate(context: GradleOutputContext? = nil) -> String {
        gradle.formatted(context: context ?? GradleOutputContext())
    }

    private struct GradleBlockContent : Equatable, Codable {
        var name: String?
        var contents: [BlockOrCommand]?

        func formatted(context: GradleOutputContext) -> String {
            var content = ""
            content += format(blocks: contents, context: context, indent: 0)
            return content
        }
    }

    private struct GradleBlock : Equatable, Codable {
        var block: String
        var param: Either<String>.Or<[String]>?
        var contents: [BlockOrCommand]?
        var enabled: Bool?

        func formatted(context: GradleOutputContext, indent: Int) -> String {
            if enabled == false {
                return ""
            }
            var content = ""
            content += format(blocks: contents, context: context, indent: indent + 4)
            return content
        }
    }


    private static func format(commandBlock: BlockOrCommand, context: GradleOutputContext, indent: Int) -> String {
        func formatCommand(_ command: String) -> String {
            String(repeating: " ", count: indent) + command + "\n"
        }

        func formatBlock(_ block: GradleBlock) -> String {
            var str = ""
            str += String(repeating: " ", count: indent)
            str += block.block
            if let params = block.param?.map({ [$0 ]}, { $0 }).value {
                str += "(" + params.joined(separator: ", ") + ")"
            }
            str += " {\n"
            str += block.formatted(context: context, indent: indent)
            str += String(repeating: " ", count: indent) + "}\n"
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
                        fromBlock.contents = (fromBlock.contents ?? []) + (block.contents ?? [])
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
