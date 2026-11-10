import Foundation
@testable import SkipSyntax
import XCTest

final class PerformanceTests: XCTestCase {
    /// Transpiles the file in the temporary directory 'performancetest.swift' file.
    ///
    /// This is meant to be run in the Profiler (right click the test and choose Profile).
    /// You may have to Build for Profiling to get source information in the Profiler.
    ///
    /// - Warning: Running in Release vs. Debug mode can have a drastic impact on results. Unit tests are typically set up to run in Debug, while the Profiler uses Release.
//    func testTemporaryDirectoryPerformanceFile() async throws {
//        let decoder = JSONDecoder()
//        var dependentModules: [CodebaseInfo.ModuleExport] = []
//        var sourceFiles: [URL] = []
//        for fileName in try FileManager.default.contentsOfDirectory(atPath: "/tmp/perftest") {
//            let file = "/tmp/perftest/" + fileName
//            if file.hasSuffix(".swift") {
//                sourceFiles.append(URL(fileURLWithPath: file))
//            } else if file.hasSuffix(".skipcode.json"), let moduleData = FileManager.default.contents(atPath: file) {
//                let module = try decoder.decode(CodebaseInfo.ModuleExport.self, from: moduleData)
//                dependentModules.append(module)
//            }
//        }
//        print("Transpiling files: \(sourceFiles)")
//        let messages = try await transpile(files: sourceFiles, dependentModules: dependentModules)
//        XCTAssertEqual(messages.count, 0)
//        for message in messages {
//            print("Message: \(message.formattedMessage)")
//        }
//    }
}
