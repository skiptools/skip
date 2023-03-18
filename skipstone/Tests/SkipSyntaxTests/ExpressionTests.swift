@testable import SkipSyntax
import XCTest

final class ExpressionTests: XCTestCase {
    func testSelf() async throws {
        try await check(swift: """
        class C {
            static func staticf() -> Int {
                return 10
            }
        
            func f() -> Int {
                return Self.staticf()
            }
        }
        """, kotlin: """
        internal open class C {
        
            internal open fun f(): Int {
                return Companion.staticf()
            }
        
            companion object {
                internal fun staticf(): Int {
                    return 10
                }
            }
        }
        """)

        try await check(swift: """
        class C {
            func instancef() -> Int {
                return 10
            }

            func f() -> Int {
                return self.instancef()
            }
        }
        """, kotlin: """
        internal open class C {
            internal open fun instancef(): Int {
                return 10
            }

            internal open fun f(): Int {
                return this.instancef()
            }
        }
        """)
    }

    func testWildcardVariable() async throws {
        try await check(swift: """
        func f() -> Int {
            let _ = f()
        }
        """, kotlin: """
        internal fun f(): Int {
            f()
        }
        """)
    }

    func testOptionalSomeNone() async throws {
        try await checkProducesMessage(swift: """
        let i: Int? = nil
        switch i {
        case .none:
            print("nil")
        case .some(1):
            print(1)
        case .some(var x):
            x += 1
            print(x)
        }
        """)
    }

    func testStaticMemberUsingClassReference() async throws {
        try await check(symbols: symbols, swift: """
        func f() {
            g(c: ExpressionTestsClass.self)
            g(c: ExpressionTestsClass.typeVar)
            ExpressionTestsClass.staticFunc()
            ExpressionTestsClass.typeVar.staticFunc()
        }

        func g(c: ExpressionTestsClass.Type) {
        }
        """, kotlin: """
        import kotlin.reflect.*
        import kotlin.reflect.full.*

        internal fun f() {
            g(c = ExpressionTestsClass::class)
            g(c = ExpressionTestsClass.typeVar)
            ExpressionTestsClass.staticFunc()
            (ExpressionTestsClass.typeVar.companionObjectInstance as ExpressionTestsClass.Companion).staticFunc()
        }

        internal fun g(c: KClass<ExpressionTestsClass>) {
        }
        """)
    }
}

private class ExpressionTestsClass {
    static let typeVar = ExpressionTestsClass.self

    static func staticFunc() {
    }
}
