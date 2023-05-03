@testable import SkipSyntax
import XCTest

final class AttributeTests: XCTestCase {
    func testAvailableAttributeIgnored() async throws {
        try await check(swift: """
        class C {
            @available(iOS 13, *)
            func f() {
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun f() = Unit
        }
        """)
    }

    func testUnavailableAttribute() async throws {
        try await check(swiftCode: {
            @available(*, unavailable, message: "this function is unimplemented")
            func someOldFunction() -> String {
                return ""
            }
            return ""
        }, kotlin: """
            @Deprecated("this function is unimplemented", level = DeprecationLevel.ERROR)
            fun someOldFunction(): String = ""
            return ""
            """)

        try await check(swiftCode: {
            @available(*, unavailable)
            func someOldFunction() -> String {
                return ""
            }
            return ""
        }, kotlin: """
            @Deprecated("\(Message.unavailableLabel)", level = DeprecationLevel.ERROR)
            fun someOldFunction(): String = ""
            return ""
            """)

        try await checkProducesMessage(swift: """
        @available(*, unavailable, message: "this function is unimplemented")
        func someOldFunction() -> String {
            return ""
        }
        someOldFunction()
        """)

        try await checkProducesMessage(swift: """
        class C {
            @available(*, unavailable)
            func someOldFunction() -> String {
                return ""
            }
        }
        {
            let c = C()
            c.someOldFunction()
        }
        """)

        try await checkProducesMessage(swift: """
        @available(*, unavailable)
        class C {
            func someOldFunction() -> String {
                return ""
            }
        }
        {
            let c = C()
            c.someOldFunction()
        }
        """)
    }

    func testDeprecatedAttribute() async throws {
        try await check(swiftCode: {
            @available(*, deprecated, message: "this function is deprecated")
            func someDepFunction() -> String {
                return ""
            }
            return ""
        }, kotlin: """
            @Deprecated("this function is deprecated")
            fun someDepFunction(): String = ""
            return ""
            """)

        try await check(swiftCode: {
            @available(*, deprecated)
            func someDepFunction() -> String {
                return ""
            }
            return ""
        }, kotlin: """
            @Deprecated("\(Message.deprecatedLabel)")
            fun someDepFunction(): String = ""
            return ""
            """)

        try await checkProducesMessage(swift: """
        @available(*, deprecated, message: "this function is deprecated")
        func someOldFunction() -> String {
            return ""
        }
        someOldFunction()
        """)

        try await checkProducesMessage(swift: """
        class C {
            @available(*, deprecated)
            func someOldFunction() -> String {
                return ""
            }
        }
        {
            let c = C()
            c.someOldFunction()
        }
        """)

        try await checkProducesMessage(swift: """
        @available(*, deprecated)
        class C {
            func someOldFunction() -> String {
                return ""
            }
        }
        {
            let c = C()
            c.someOldFunction()
        }
        """)
    }

    func testIfAvailableIsTrue() async throws {
        try await check(swift: """
        func f() {
            if #available(iOS 13, *) {
                print("ok")
            } else {
                print("nope")
            }
        }
        """, kotlin: """
        internal fun f() {
            if (true) {
                print("ok")
            } else {
                print("nope")
            }
        }
        """)
    }
}
