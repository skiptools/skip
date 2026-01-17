// Copyright (c) 2023 - 2026 Skip
// Licensed under the GNU Affero General Public License v3.0
// SPDX-License-Identifier: AGPL-3.0-only

import SkipSyntax
import XCTest

final class DynamicSupportTests: XCTestCase {
    private var transformers: [KotlinTransformer] {
        return builtinKotlinTransformers() + [KotlinBridgeTransformer(), KotlinDynamicObjectTransformer(root: "X")]
    }

    func testTypealias() async throws {
        try await check(swiftBridge: """
        typealias Calendar = X.java.util.Calendar
        typealias Date = X.java.util.Date
        typealias BigInteger = X.java.math.BigInteger
        typealias None = java.lang.None
        """, kotlin: """
        """, swiftBridgeSupport: """
        enum X {}
        extension X { enum java {} }
        extension X.java { enum math {} }
        extension X.java.math {
            final class BigInteger: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.math.BigInteger", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.math.BigInteger", options: options)
                }
            }
        }
        extension X.java { enum util {} }
        extension X.java.util {
            final class Calendar: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar", options: options)
                }
            }
        }
        extension X.java.util {
            final class Date: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.util.Date", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.util.Date", options: options)
                }
            }
        }
        """, bridgeDecodeLevel: .full, transformers: transformers)
    }

    func testConstructor() async throws {
        try await check(swiftBridge: """
        func f() {
            let date = X.java.util.Date(999)
            self.g(p: X.java.util.Calendar().year)
        }
        """, kotlin: """
        """, swiftBridgeSupport: """
        enum X {}
        extension X { enum java {} }
        extension X.java { enum util {} }
        extension X.java.util {
            final class Calendar: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar", options: options)
                }
            }
        }
        extension X.java.util {
            final class Date: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.util.Date", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.util.Date", options: options)
                }
            }
        }
        """, bridgeDecodeLevel: .full, transformers: transformers)
    }

    func testStatics() async throws {
        try await check(swiftBridge: """
        func f() {
            self.g(p: X.java.util.Calendar.Companion.YEAR)
        }
        """, kotlin: """
        """, swiftBridgeSupport: """
        enum X {}
        extension X { enum java {} }
        extension X.java { enum util {} }
        extension X.java.util {
            final class Calendar: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar", options: options)
                }
            }
        }
        """, bridgeDecodeLevel: .full, transformers: transformers)
    }

    func testUnsupportedSwift() async throws {
        // We can't add protocols to builtin types, but this should not bubble up to user
        try await check(swiftBridge: """
        protocol P {
            func f()
        }
        extension Int: P {
            func f() {
                let calendarType = X.java.util.Calendar.self
            }
        }
        """, kotlin: """
        """, swiftBridgeSupport: """
        enum X {}
        extension X { enum java {} }
        extension X.java { enum util {} }
        extension X.java.util {
            final class Calendar: AnyDynamicObject {
                init(options: JConvertibleOptions = .kotlincompat, _ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", options: options, arguments: arguments)
                }
                required init(for object: JavaObjectPointer, options: JConvertibleOptions = .kotlincompat) throws {
                    try super.init(for: object, options: options)
                }
                static func Companion(options: JConvertibleOptions = .kotlincompat) -> AnyDynamicObject {
                    return try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar", options: options)
                }
            }
        }
        """, bridgeDecodeLevel: .full, transformers: transformers)
    }
}
