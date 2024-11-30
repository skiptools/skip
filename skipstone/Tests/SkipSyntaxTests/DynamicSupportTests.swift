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
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.math.BigInteger", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.math.BigInteger")
            }
        }
        extension X.java { enum util {} }
        extension X.java.util {
            final class Calendar: AnyDynamicObject {
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar")
            }
        }
        extension X.java.util {
            final class Date: AnyDynamicObject {
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.util.Date", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.util.Date")
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
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar")
            }
        }
        extension X.java.util {
            final class Date: AnyDynamicObject {
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.util.Date", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.util.Date")
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
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar")
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
                init(_ arguments: Any?...) throws {
                    try super.init(className: "java.util.Calendar", arguments: arguments)
                }
                required init(for object: JavaObjectPointer) throws {
                    try super.init(for: object)
                }
                static let Companion = try! AnyDynamicObject(forStaticsOfClassName: "java.util.Calendar")
            }
        }
        """, bridgeDecodeLevel: .full, transformers: transformers)
    }
}
