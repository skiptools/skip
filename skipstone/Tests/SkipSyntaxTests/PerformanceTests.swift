import Foundation
import XCTest

final class PerformanceTests: XCTestCase {
    /// Transpiles the file in the temporary directory 'performancetest.swift' file.
    ///
    /// This is meant to be run in the Profiler (right click the test and choose Profile).
    ///
    /// - Warning: Running in Release vs. Debug mode can have a drastic impact on results. Unit tests are typically set up to run in Debug, while the Profiler uses Release.
//    func testTemporaryDirectoryPerformanceFile() async throws {
//        let srcURL = URL(fileURLWithPath: "/tmp/performancetest.swift")
//        print("Transpiling file: \(srcURL.absoluteURL.path(percentEncoded: false))")
//        let messages = try await transpile(file: srcURL)
//        XCTAssertEqual(messages.count, 0)
//    }
}
