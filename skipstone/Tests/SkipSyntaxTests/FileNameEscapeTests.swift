// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

@testable import SkipSyntax
import XCTest

final class FileNameEscapeTests: XCTestCase {

    func testSwiftIdentifierEscaping() {
        // Valid Swift identifier characters (ASCII alphanumerics and `_`) pass through.
        XCTAssertEqual("Model_ExtensionsKt".swiftIdentifierEscaped, "Model_ExtensionsKt")
        // Invalid characters are escaped as `_0XXXX` per UTF-16 code unit.
        XCTAssertEqual("Model+BridgingKt".swiftIdentifierEscaped, "Model_0002bBridgingKt")
        XCTAssertEqual("Model.generatedKt".swiftIdentifierEscaped, "Model_0002egeneratedKt")
        // A character outside the BMP is a UTF-16 surrogate pair; both units escape.
        XCTAssertEqual("A🎉Kt".swiftIdentifierEscaped, "A_0d83c_0df89Kt")
    }

    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer()]
    }

    // A file name character that is invalid in a Swift identifier (the "+") must be
    // escaped in the generated `@_cdecl` function name, or the bridge fails to
    // compile (issue #63). Both the JNI symbol and the Swift name escape it here.
    func testBridgeFunctionNameEscapesInvalidFileNameCharacters() async throws {
        try await check(swiftBridge: """
        public var i = 1
        """, swiftBridgeFileName: "Model+Bridging.swift", kotlin: """
        var i: Int
            get() = Swift_i()
            set(newValue) {
                Swift_i_set(newValue)
            }
        private external fun Swift_i(): Int
        private external fun Swift_i_set(value: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_Model_0002bBridgingKt_Swift_1i")
        public func Model_0002bBridgingKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        @_cdecl("Java_Model_0002bBridgingKt_Swift_1i_1set")
        public func Model_0002bBridgingKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int32) {
            i = Int(value)
        }
        """, transformers: transformers)
    }

    // An underscore is valid in a Swift identifier, so the Swift `@_cdecl` function
    // name must keep it as-is; only the JNI symbol mangles it to `_1` (issue #63).
    func testBridgeFunctionNamePreservesUnderscoreInFileName() async throws {
        try await check(swiftBridge: """
        public var i = 1
        """, swiftBridgeFileName: "Model_Extensions.swift", kotlin: """
        var i: Int
            get() = Swift_i()
            set(newValue) {
                Swift_i_set(newValue)
            }
        private external fun Swift_i(): Int
        private external fun Swift_i_set(value: Int)
        """, swiftBridgeSupport: """
        @_cdecl("Java_Model_1ExtensionsKt_Swift_1i")
        public func Model_ExtensionsKt_Swift_i(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer) -> Int32 {
            return Int32(i)
        }
        @_cdecl("Java_Model_1ExtensionsKt_Swift_1i_1set")
        public func Model_ExtensionsKt_Swift_i_set(_ Java_env: JNIEnvPointer, _ Java_target: JavaObjectPointer, _ value: Int32) {
            i = Int(value)
        }
        """, transformers: transformers)
    }
}
