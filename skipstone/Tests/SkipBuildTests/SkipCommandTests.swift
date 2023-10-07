import XCTest
@testable import SkipBuild
import TSCBasic

final class SkipCommandTests: XCTestCase {
    func testVersionCommand() async throws {
        try await XCTAssertEqualAsync(skipVersion.json(), skipstone(["version", "-j"]).json()["version"])
    }

    func testInfoCommand() async throws {
        _ = try await skipstone(["info", "-jA"]).json()
    }

    func testDoctorCommand() async throws {
        // run skip doctor with JSON array output and make sure we can parse the result
        try await XCTAssertEqualAsync(["msg": "Skip Doctor"], skipstone(["doctor", "-jA"]).json().array?.first)
    }

    func testLibInitCommand() async throws {
        let basicProject = try await libInitComand(projectName: "basicProject", moduleNames: "SomeModule")
        XCTAssertEqual(basicProject ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  └─ SomeModule
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     ├─ Skip
        │     │  └─ skip.yml
        │     └─ SomeModule.swift
        └─ Tests
           └─ SomeModuleTests
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              ├─ SomeModuleTests.swift
              └─ XCSkipTests.swift

        """)
    }

    func testLibInitAppCommand() async throws {
        let basicProject = try await libInitComand(projectName: "cool-app", appid: "some.cool.app", moduleNames: "CoolApp", "CoolModel")
        XCTAssertEqual(basicProject ?? "", """
        .
        ├─ Package.swift
        ├─ README.md
        ├─ Sources
        │  ├─ CoolApp
        │  │  ├─ CoolApp.swift
        │  │  ├─ Resources
        │  │  │  └─ Localizable.xcstrings
        │  │  └─ Skip
        │  │     ├─ AndroidManifest.xml
        │  │     └─ skip.yml
        │  └─ CoolModel
        │     ├─ CoolModel.swift
        │     ├─ Resources
        │     │  └─ Localizable.xcstrings
        │     └─ Skip
        │        └─ skip.yml
        └─ Tests
           ├─ CoolAppTests
           │  ├─ CoolAppTests.swift
           │  ├─ Resources
           │  │  └─ TestData.json
           │  ├─ Skip
           │  │  └─ skip.yml
           │  └─ XCSkipTests.swift
           └─ CoolModelTests
              ├─ CoolModelTests.swift
              ├─ Resources
              │  └─ TestData.json
              ├─ Skip
              │  └─ skip.yml
              └─ XCSkipTests.swift
        
        """)
    }

    func libInitComand(projectName: String, appid: String? = nil, resourcePath: String? = "Resources", moduleNames: String...) async throws -> String? {
        let tmpDir = URL(fileURLWithPath: UUID().uuidString, isDirectory: true, relativeTo: URL(fileURLWithPath: NSTemporaryDirectory() + "/testLibInitCommand/", isDirectory: true))
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        var cmd = ["lib", "init", "-jA", "--no-build", "--no-test", "--tree"]
        if let resourcePath = resourcePath {
            cmd += ["--resource-path", resourcePath]
        }
        if let appid = appid {
            cmd += ["--appid", appid]
        }
        cmd += ["-d", tmpDir.path]

        cmd += [projectName]
        cmd += moduleNames

        let created = try await skipstone(cmd).json()
        XCTAssertEqual(created.array?.first, ["msg": .string("Initializing Skip library \(projectName)")])
        // return the tree output, which is in the 2nd-to-last message
        return created.array?.dropLast().last?["msg"]?.string
    }
}


/// Cover for `XCTAssertEqual` that permit async autoclosures.
@available(macOS 13, iOS 16, tvOS 16, watchOS 8, *)
func XCTAssertEqualAsync<T>(_ expression1: T, _ expression2: T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) where T : Equatable {
    XCTAssertEqual(expression1, expression2, message(), file: file, line: line)
}
