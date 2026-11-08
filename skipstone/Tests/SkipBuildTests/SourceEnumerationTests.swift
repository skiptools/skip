// Copyright (c) 2026 Skip

import Foundation
import XCTest
@testable import SkipBuild

final class SourceEnumerationTests: XCTestCase {
    func testTargetDirectorySymlinkPreservesLogicalPaths() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("OriginalTarget")
        let link = root.appendingPathComponent("MirroredTarget")
        try manager.createDirectory(at: target.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        try "first".write(to: target.appendingPathComponent("First.swift"), atomically: true, encoding: .utf8)
        try "second".write(to: target.appendingPathComponent("Nested/Second.swift"), atomically: true, encoding: .utf8)
        try "hidden".write(to: target.appendingPathComponent(".Hidden.swift"), atomically: true, encoding: .utf8)
        try "external".write(to: root.appendingPathComponent("ExternalSource.swift"), atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(at: target.appendingPathComponent("External.swift"), withDestinationURL: root.appendingPathComponent("ExternalSource.swift"))
        try manager.createSymbolicLink(at: link, withDestinationURL: target)

        for folder in [target, link] {
            let sources = try manager.enumeratedURLs(of: folder)
            XCTAssertEqual(Set(sources), Set(["First.swift", "Nested/Second.swift", "External.swift"].map(folder.appendingPathComponent)))
            XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Nested/Second.swift"), encoding: .utf8), "second")
        }
    }

    func testDarwinTemporaryDirectoryAliasesPreserveRequestedPaths() throws {
        #if os(macOS)
        let manager = FileManager.default
        let name = UUID().uuidString
        let privateRoot = URL(fileURLWithPath: "/private/tmp/\(name)", isDirectory: true)
        let publicRoot = URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true)
        try manager.createDirectory(at: privateRoot.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: privateRoot) }
        try "source".write(to: privateRoot.appendingPathComponent("Nested/Source.swift"), atomically: true, encoding: .utf8)
        for folder in [privateRoot, publicRoot] {
            XCTAssertEqual(try manager.enumeratedURLs(of: folder), [folder.appendingPathComponent("Nested/Source.swift")])
        }
        #endif
    }

    func testUnexpectedEnumeratorPrefixKeepsOriginalURL() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let target = root.appendingPathComponent("Target")
        let sibling = root.appendingPathComponent("TargetSibling")
        try manager.createDirectory(at: target, withIntermediateDirectories: true)
        try manager.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let outside = sibling.appendingPathComponent("Source.swift")
        try "outside".write(to: outside, atomically: true, encoding: .utf8)

        // Exercise an unexpected provider result, including a misleading string prefix.
        let logical = root.appendingPathComponent("MirroredTarget")
        XCTAssertEqual(FileManager.enumeratedURL(outside, from: target, under: logical), outside)
        XCTAssertEqual(FileManager.enumeratedURL(outside, from: target.appendingPathComponent("Deeper"), under: logical), outside)
    }
}
