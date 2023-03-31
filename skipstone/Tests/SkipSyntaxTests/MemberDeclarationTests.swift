@testable import SkipSyntax
import XCTest

final class MemberDeclarationTests: XCTestCase {
    func testOptionalVariableInitialization() async throws {
        try await check(swift: """
        class A {
            var i: Int?
            var j: Int? = nil
            var k = 10
        }
        """, kotlin: """
        internal open class A {
            internal var i: Int? = null
            internal var j: Int? = null
            internal var k = 10
        }
        """)
    }

    func testStaticMembers() async throws {
        try await check(swift: """
        class A {
            static let staticLet = 1
            static var staticVar = 10

            static func staticFunc() -> Int {
                return 20
            }

            var i = 1
        }
        """, kotlin: """
        internal open class A {

            internal var i = 1

            companion object {
                internal val staticLet = 1
                internal var staticVar = 10

                internal fun staticFunc(): Int {
                    return 20
                }
            }
        }
        """)
    }

    func testComputedVariableGetSet() async throws {
        try await check(swift: """
        class A {
            var i: Int {
                return 10
            }
            var j: Int {
                get {
                    return 10
                }
                set {
                    print(newValue)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open val i: Int
                get() {
                    return 10
                }
            internal open var j: Int
                get() {
                    return 10
                }
                set(newValue) {
                    print(newValue)
                }
        }
        """)

        // Custom set label
        try await check(swift: """
        class A {
            var i: Int {
                get {
                    return 10
                }
                set(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal open var i: Int
                get() {
                    return 10
                }
                set(newValue) {
                    val value = newValue
                    print(value)
                }
        }
        """)
    }

    func testVariableWillDidSet() async throws {
        try await check(swift: """
        class A {
            var i = 1 {
                willSet {
                    print(newValue)
                }
            }
            var j = 2 {
                didSet {
                    print(j == 2)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    print(newValue)
                    field = newValue
                }
            internal var j = 2
                set(newValue) {
                    val oldValue = field
                    field = newValue
                    print(j == 2)
                }
        }
        """)

        // Custom willSet label
        try await check(swift: """
        class A {
            var i = 1 {
                willSet(value) {
                    print(value)
                }
            }
        }
        """, kotlin: """
        internal open class A {
            internal var i = 1
                set(newValue) {
                    val value = newValue
                    print(value)
                    field = newValue
                }
        }
        """)
    }

    func testMutableStructVariableWillDidSet() async throws {
        try await check(swift: """
        struct A {
              var i = 1 {
                  willSet {
                      print(newValue)
                  }
              }
              var j = 2 {
                  didSet {
                      print(j == 2)
                  }
              }
        }
        """, kotlin: """
        internal class A: MutableStruct {
            internal var i = 1
                set(newValue) {
                    willmutate()
                    try {
                        if (!isconstructing) {
                            print(newValue)
                        }
                        field = newValue
                    } finally {
                        didmutate()
                    }
                }
            internal var j = 2
                set(newValue) {
                    willmutate()
                    try {
                        val oldValue = field
                        field = newValue
                        if (!isconstructing) {
                            print(j == 2)
                        }
                    } finally {
                        didmutate()
                    }
                }

            constructor(i: Int = 1, j: Int = 2) {
                isconstructing = true
                try {
                    this.i = i
                    this.j = j
                } finally {
                    isconstructing = false
                }
            }

            override var supdate: ((Any) -> Unit)? = null
            override var smutatingcount = 0
            override fun scopy(): MutableStruct {
                return A(i, j)
            }

            private var isconstructing = false
        }
        """)
    }

    func testPropertySideEffectOrdering() {
        sideEffectOrdering = []
        let cls = MemberDeclarationTestsSideEffectsClass()
        XCTAssertEqual([], sideEffectOrdering)
        cls.sideEffectsStruct.i += 1
        XCTAssertEqual(["willSetI", "didSetI", "willSetOwner", "didSetOwner"], sideEffectOrdering)

        sideEffectOrdering = []
        cls.sideEffectsStruct.j += 1
        XCTAssertEqual(["willSetJ", "willSetI", "didSetI", "willSetI", "didSetI", "didSetJ", "willSetOwner", "didSetOwner"], sideEffectOrdering)
    }

    func testDiscardableResult() async throws {
        try await check(swift: """
        @discardableResult func f() -> Int {
            return 1
        }
        """, kotlin: """
        internal fun f(): Int {
            return 1
        }
        """)
    }

    func testInOutParameter() async throws {
        try await check(swift: """
        func f(param: inout Int) {
            param += 1
        }
        func f2() {
            var i = 0
            f(param: &i)
            print(i)
        }
        """, kotlin: """
        internal fun f(param: InOut<Int>) {
            param.value += 1
        }
        internal fun f2() {
            var i = 0
            f(param = InOut({ i }, { i = it }))
            print(i)
        }
        """)

        // Test struct references
        try await check(swift: """
        func f(param s: inout Struct) -> Struct {
            s.member = Struct()
            var s2 = s
            s2.member = s.member
            return s2
        }
        func f2() {
            var s = Struct()
            let s2 = f(param: &s)
            print(s.member == s2.member)
        }
        """, kotlin: """
        internal fun f(param: InOut<Struct>): Struct {
            val s = param
            s.value.member = Struct()
            var s2 = s.value.sref()
            s2.member = s.value.member.sref()
            return s2.sref()
        }
        internal fun f2() {
            var s = Struct()
            val s2 = f(param = InOut({ s }, { s = it }))
            print(s.member == s2.member)
        }
        """)

        try await check(swift: """
        func f(param: inout Int) {
            param += 1
            f(param: &param)
        }
        """, kotlin: """
        internal fun f(param: InOut<Int>) {
            param.value += 1
            f(param = InOut({ param.value }, { param.value = it }))
        }
        """)
    }

    func testOverrideProtocolMember() async throws {
        try await check(supportingSwift: """
        protocol P {
            var i: Int { get }
            func f()
        }
        """, swift: """
        class PImpl: P {
            var i = 0
            func f() {
            }
        }
        """, kotlin: """
        internal open class PImpl: P {
            override var i = 0
            override fun f() {
            }
        }
        """)
    }

    func testSubscript() async throws {
        try await check(expectFailure: true, swift: """
        class C {
            subscript(index: Int) -> Int {
                get {
                    return 0
                }
                set {
                }
            }
            subscript(key: String, defaultValue: Int) -> Int {
                return defaultValue
            }
        }
        """, kotlin: """
        internal open class C {
            internal operator fun get(index: Int): Int {
                return 0
            }
            internal operator fun set(index: Int, newValue: Int) {
            }
            internal operator fun get(key: String, defaultValue: Int): Int {
                return defaultValue
            }
        }
        """)
    }

    func testFunctionSignatureConflicts() async throws {
        try await check(swift: """
        func f(a: Int) {
        }
        func f(c: Int) {
        }
        func f(b: Int) {
        }
        func f(a: Double) {
        }
        func g(a: Int) {
        }
        """, kotlin: """
        internal fun f(a: Int, unusedp_0: Nothing? = null) {
        }
        internal fun f(c: Int) {
        }
        internal fun f(b: Int, unusedp_0: Nothing? = null, unusedp_1: Nothing? = null) {
        }
        internal fun f(a: Double) {
        }
        internal fun g(a: Int) {
        }
        """)
    }

    func testMemberFunctionSignatureConflicts() async throws {
        try await check(swift: """
        class A {
            func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int, unusedp_0: Nothing? = null) {
            }
            internal open fun f(b: Int) {
            }
        }
        """)

        try await check(swift: """
        open class A {
            open func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        """, kotlin: """
        open class A {
            open fun f(a: Int) {
            }
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }

            companion object {
            }
        }
        """)

        try await check(swift: """
        class A {
            func f(a: Int) {
            }
        }
        class B: A {
            func f(b: Int) {
            }
        }
        class C {
            func f(c: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int) {
            }
        }
        internal open class B: A() {
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal open class C {
            internal open fun f(c: Int) {
            }
        }
        """)

        try await check(swift: """
        class A {
            func f(a: Int) {
            }
        }
        class B: A {
            override func f(a: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int) {
            }
        }
        internal open class B: A() {
            override fun f(a: Int) {
            }
        }
        """)

        // Make sure we aren't dependent on param alpha order
        try await check(swift: """
        class A {
            func f(c: Int) {
            }
        }
        class B: A {
            func f(b: Int) {
            }
        }
        class C {
            func f(a: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(c: Int) {
            }
        }
        internal open class B: A() {
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal open class C {
            internal open fun f(a: Int) {
            }
        }
        """)

        try await check(swift: """
        class A {
            func f(a: Int) {
            }
            func g(z: Int) {
            }
        }
        class B: A {
            func f(b: Int) {
            }
        }
        class C: B {
            func f(c: Int) {
            }
            func g(a: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal open fun f(a: Int) {
            }
            internal open fun g(z: Int) {
            }
        }
        internal open class B: A() {
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal open class C: B() {
            internal open fun f(c: Int, unusedp_0: Nothing? = null, unusedp_1: Nothing? = null) {
            }
            internal open fun g(a: Int, unusedp_0: Nothing? = null) {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        open class A {
            open func f(a: Int) {
            }
            open func f(b: Int) {
            }
        }
        """)
    }

    func testProtocolFunctionSignatureConflicts() async throws {
        try await check(swift: """
        class A: P {
            func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        protocol P {
            func f(a: Int)
        }
        """, kotlin: """
        internal open class A: P {
            override fun f(a: Int) {
            }
            internal open fun f(b: Int, unusedp_0: Nothing? = null) {
            }
        }
        internal interface P {
            fun f(a: Int)
        }
        """)

        try await check(swift: """
        protocol P1 {
            func f(a: Int)
        }
        protocol P2 {
            func f(a: Double)
        }
        protocol P3: P1, P2 {
            func f(b: Int)
        }
        class A: P1 {
            func f(a: Int) {
            }
        }
        class B: P2, P3 {
            func f(a: Int) {
            }
            func f(a: Double) {
            }
            func f(b: Int) {
            }
        }
        """, kotlin: """
        internal interface P1 {
            fun f(a: Int)
        }
        internal interface P2 {
            fun f(a: Double)
        }
        internal interface P3: P1, P2 {
            fun f(b: Int, unusedp_0: Nothing? = null)
        }
        internal open class A: P1 {
            override fun f(a: Int) {
            }
        }
        internal open class B: P2, P3 {
            override fun f(a: Int) {
            }
            override fun f(a: Double) {
            }
            override fun f(b: Int, unusedp_0: Nothing?) {
            }
        }
        """)

        try await checkProducesMessage(swift: """
        class A: P1, P2 {
            func f(a: Int) {
            }
            func f(b: Int) {
            }
        }
        public protocol P1 {
            func f(a: Int)
        }
        public protocol P2 {
            func f(b: Int)
        }
        """)
    }

    func testInitSignatureConflicts() async throws {
        try await check(swift: """
        class A {
            init(a: Int) {
            }
            init(b: Int) {
            }
        }
        class B: A {
            override init(a: Int) {
            }
            init(c: Int) {
            }
        }
        class C: A {
            init(c: Int) {
            }
        }
        """, kotlin: """
        internal open class A {
            internal constructor(a: Int, unusedp_0: Nothing? = null) {
            }
            internal constructor(b: Int) {
            }
        }
        internal open class B: A {
            internal constructor(a: Int, unusedp_0: Nothing? = null): super() {
            }
            internal constructor(c: Int): super() {
            }
        }
        internal open class C: A {
            internal constructor(c: Int): super() {
            }
        }
        """)
    }

    func testLocalFunctions() async throws {
        try await checkProducesMessage(swift: """
        func f() -> Int {
            func g() -> Int {
                return 1
            }
            return g() + 1
        }
        """)
    }
}

var sideEffectOrdering: [String] = []

private struct MemberDeclarationTestsSideEffectsStruct {
    var i = 0 {
        willSet {
            sideEffectOrdering.append("willSetI")
        }
        didSet {
            sideEffectOrdering.append("didSetI")
        }
    }

    var j = 0 {
        willSet {
            sideEffectOrdering.append("willSetJ")
            i += 1
        }
        didSet {
            i -= 1
            sideEffectOrdering.append("didSetJ")
        }
    }
}

private class MemberDeclarationTestsSideEffectsClass {
    fileprivate var sideEffectsStruct = MemberDeclarationTestsSideEffectsStruct() {
        willSet {
            sideEffectOrdering.append("willSetOwner")
        }
        didSet {
            sideEffectOrdering.append("didSetOwner")
        }
    }
}
