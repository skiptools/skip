// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import SkipSyntax
import XCTest

final class FileNameEscapeTests: XCTestCase {
    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer()]
    }

    // A source file whose name contains characters that are invalid in a Swift
    // identifier (e.g. the "+" in `Model+Bridging.swift`) is used to derive both
    // the JNI symbol (already escaped) and the generated `@_cdecl` Swift function
    // name. The Swift-identifier side must be escaped too, or the generated
    // bridging code fails to compile (issue #63).
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
}
