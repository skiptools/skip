@testable import SkipSyntax
import XCTest

final class AttributeAndModifierTests: XCTestCase {
    func testVisibility() async throws {
        try await check(swift: """
        class A {
        }
        open class A {
        }
        public class A {
        }
        internal class A {
        }
        fileprivate class A {
        }
        private class A {
        }
        """, kotlin: """
        internal open class A {
        }
        open class A {

            companion object {
            }
        }
        open class A {

            companion object {
            }
        }
        internal open class A {
        }
        private open class A {
        }
        private open class A {
        }
        """)

        try await check(swift: """
        class A {
            open class A {
            }
            public class A {
            }
            internal class A {
            }
            fileprivate class A {
            }
            private class A {
            }
        }
        """, kotlin: """
        internal open class A {
            open class A {

                companion object {
                }
            }
            open class A {

                companion object {
                }
            }
            internal open class A {
            }
            internal open class A {
            }
            private open class A {
            }
        }
        """)

        try await check(swift: """
        class A {
            let v = 1
            public let v = 1
            internal let v = 1
            fileprivate let v = 1
            private let v = 1
        }
        let v = 1
        public let v = 1
        internal let v = 1
        fileprivate let v = 1
        private let v = 1
        """, kotlin: """
        internal open class A {
            internal val v = 1
            val v = 1
            internal val v = 1
            internal val v = 1
            private val v = 1
        }
        internal val v = 1
        val v = 1
        internal val v = 1
        private val v = 1
        private val v = 1
        """)

        try await check(swift: """
        class C {
            public internal(set) var v1 = 1
            private(set) var v2 = 1
            private(set) var a = [1]
            private(set) var b: [Int] {
                get {
                    return [1]
                }
                set {
                }
            }
        }
        class D: C {
            private(set) override var b: [Int] {
                get {
                    return [2]
                }
                set {
                }
            }
        }
        """, kotlin: """
        internal open class C {
            open var v1 = 1
                internal set
            internal var v2 = 1
                private set
            internal var a = arrayOf(1)
                get() = field.sref({ this.a = it })
                private set(newValue) {
                    field = newValue.sref()
                }
            internal open var b: Array<Int>
                get() = arrayOf(1).sref({ this.b = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                }
        }
        internal open class D: C() {
            override var b: Array<Int>
                get() = arrayOf(2).sref({ this.b = it })
                set(newValue) {
                    @Suppress("NAME_SHADOWING") val newValue = newValue.sref()
                }
        }
        """)
    }

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
