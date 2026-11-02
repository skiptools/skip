// Copyright (c) 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
import TSCBasic
@testable import SkipBuild

final class PackageRootTests: XCTestCase {
    func testConventionalTargetsKeepTheirPackageRoot() throws {
        let fs = InMemoryFileSystem()
        let root = try makePackage("/component", fs: fs)
        for path in ["Sources/Component", "Tests/ComponentTests"] {
            XCTAssertEqual(root, try SkipstoneCommand.packageRoot(containing: root.appending(components: path.split(separator: "/").map(String.init)), fs: fs))
        }
    }

    func testCustomTargetPathsUseTheirOwningManifest() throws {
        let fs = InMemoryFileSystem()
        let root = try makePackage("/component", fs: fs)
        for path in [root, root.appending(component: "Custom"), root.appending(components: "Custom", "Deep", "Target")] {
            XCTAssertEqual(root, try SkipstoneCommand.packageRoot(containing: path, fs: fs))
        }
    }

    func testNearestManifestWinsForNestedPackage() throws {
        let fs = InMemoryFileSystem()
        let root = try makePackage("/component", fs: fs)
        let nested = try makePackage("/component/Tests", fs: fs)
        XCTAssertEqual(root, try SkipstoneCommand.packageRoot(containing: root.appending(components: "Sources", "Component"), fs: fs))
        XCTAssertEqual(nested, try SkipstoneCommand.packageRoot(containing: nested.appending(component: "ComponentTests"), fs: fs))
    }

    func testMissingManifestFails() throws {
        XCTAssertThrowsError(try SkipstoneCommand.packageRoot(containing: AbsolutePath(validating: "/missing/Target"), fs: InMemoryFileSystem())) { error in
            XCTAssertEqual(String(describing: error), "No Package.swift found above /missing/Target")
        }
    }

    func testNativeMirrorsUseCustomAndNestedPackageManifests() async throws {
        let fs = localFileSystem
        let root = try AbsolutePath(validating: NSTemporaryDirectory()).appending(component: UUID().uuidString)
        defer { try? fs.removeFileTree(root) }

        for (index, layout) in [(["Custom", "Deep", "Native"], false), (["Tests", "NativeTests"], true), (["Native"], false)].enumerated() {
            let package = root.appending(component: "case\(index)")
            let target = package.appending(components: layout.0)
            let owner = layout.1 ? package.appending(component: "Tests") : package
            let skipFolder = target.appending(component: "Skip")
            try fs.createDirectory(skipFolder, recursive: true)
            try fs.writeFileContents(package.appending(component: "Package.swift"), bytes: "// outer manifest\n")
            let manifest = "// swift-tools-version: 6.1\n// owning package \(index)\n"
            try fs.writeFileContents(owner.appending(component: "Package.swift"), bytes: ByteString(encodingAsUTF8: manifest))
            try fs.writeFileContents(target.appending(component: "Native.swift"), bytes: "public let value = 1\n")
            try fs.writeFileContents(skipFolder.appending(component: "skip.yml"), bytes: "skip:\n  mode: 'native'\n")

            let moduleRoot = package.appending(components: ".build", "outputs", "Native")
            let output = moduleRoot.appending(components: "src", "main")
            _ = try await skipstone([
                "skipstone", "--project", target.pathString,
                "--skip-folder", skipFolder.pathString,
                "--sourcehash", moduleRoot.appending(component: ".sourcehash").pathString,
                "--output-folder", output.pathString,
                "--module-root", moduleRoot.pathString,
                "--module", "Native:" + target.pathString,
            ])
            XCTAssertEqual(manifest, try fs.readFileContents(output.appending(components: "swift", "Package.swift")).description)
        }
    }

    private func makePackage(_ path: String, fs: InMemoryFileSystem) throws -> AbsolutePath {
        let root = try AbsolutePath(validating: path)
        try fs.createDirectory(root, recursive: true)
        try fs.writeFileContents(root.appending(component: "Package.swift")) { $0.write("// package") }
        return root
    }
}
